# A transaction represents
class Transaction < ApplicationRecord
  belongs_to :account, optional: false

  belongs_to :category, optional: true
  belongs_to :counterparty, class_name: "Account", foreign_key: "counterparty_id",
             inverse_of: :counterparty_transactions, optional: true
  belongs_to :import_matcher, optional: true

  validates :date, presence: true
  validates :amount, presence: true

  validate :counterparty_name_resolved

  monetize :amount_pence
  monetize :balance_pence, allow_nil: true

  # Statement order: newest first, with day_index separating transactions that share a date and id as a
  # final tiebreaker so the ordering is total.  day_index is null on transactions added by hand through
  # the UI, which never run #sequence, so it is coalesced rather than compared directly — a null would
  # otherwise drop those rows out of every keyset comparison below.
  ORDER = "transactions.date DESC, COALESCE(transactions.day_index, 0) DESC, transactions.id DESC".freeze

  scope :newest_first, -> { order(Arel.sql(ORDER)) }

  scope :on_or_before, ->(date) { where(date: ..date) }

  # Outgoings only.  Income and refunds are positive and have no place in a forecast of what will be
  # spent — a month's salary landing in an uncategorised bucket would swamp everything around it.
  scope :spend, -> { where(amount_pence: ...0) }

  # Everything strictly older than one row, in the ordering above.  Keyset rather than offset paging, so
  # that adding a transaction while someone is scrolling neither repeats nor skips a row.
  scope :older_than, ->(date, day_index, id) {
    where(
      "transactions.date < :date
       OR (transactions.date = :date AND COALESCE(transactions.day_index, 0) < :day_index)
       OR (transactions.date = :date AND COALESCE(transactions.day_index, 0) = :day_index
           AND transactions.id < :id)",
      date: date, day_index: day_index, id: id
    )
  }

  # The counterparty as typed into the transaction list, which offers the existing names through a datalist
  # rather than a select — twenty selects over a few hundred counterparties would be thousands of options on
  # one page.
  attr_reader :counterparty_name

  # The name a second save would create, or nil.  The row round-trips it through a hidden field and hands it
  # back as #confirmed_counterparty_name, and keeps its save button on offer while it is set.
  attr_reader :counterparty_to_confirm

  # The name the previous response offered to create, handed back by the row.  A plain accessor with no side
  # effects, because strong params assign attributes in the order the form submitted them and nothing here
  # may depend on whether this arrives before or after #counterparty_name=.  It carries the *name* rather
  # than a bare "yes", so editing the field before saving again asks about the new name instead of quietly
  # creating the old one.
  attr_accessor :confirmed_counterparty_name

  before_validation :accept_confirmed_counterparty

  # Blank clears the counterparty.  A name matching none is not created outright — counterparty names are
  # already sprawling, because AnalysisImporter derived them from raw statement text, and a typo would add to
  # that — but neither is it refused: the row comes back marked, and saving it again creates the record.
  # The confirmation itself is handled by #accept_confirmed_counterparty, so this stays a lookup.
  #
  # A value that already names this transaction's counterparty is left alone rather than resolved again.
  # #counterparty is an Account, and import data or the console can point it at one of the household's own
  # accounts; the cell then renders that account's name, which Counterparty does not contain, so submitting
  # the row — even to change nothing but the category — used to fail on a name the user never typed.
  # Resolving a *changed* name still goes through Counterparty only, so an own account can be neither chosen
  # nor created.
  # @param [String, nil] value
  def counterparty_name=(value)
    @counterparty_name = value
    @unresolved_counterparty = nil

    if value.blank?
      self.counterparty = nil
    elsif !counterparty&.name&.casecmp?(value.squish)
      match = Counterparty.named(value).first
      match ? self.counterparty = match : @unresolved_counterparty = value
    end
  end

  # True once a confirmed name was turned into a new Counterparty.  After a successful save that record
  # exists, and its name belongs in the page's datalist alongside the rest.
  # @return [Boolean]
  def counterparty_created?
    @counterparty_created == true
  end

  # Find if a match for this trx exists using the ImportMatcher class.
  #
  # @param [Enumerable<ImportMatcher>, nil] matchers the rules to consider, where the caller has already
  #   loaded them — see ImportMatcher.find_match for why an importer should.
  # @return [Transaction]
  def find_match(matchers = nil)
    match = ImportMatcher.find_match(self, matchers)

    if match
      self.import_matcher_id = match.id
      self.counterparty = match.counterparty
      self.category_id = match.category_id
    end
  end

  # Add an imported transaction to the account, taking account of whether other transactions have already been added.
  #
  # The running balance is chained off the transaction before this one, so everything here depends on that
  # predecessor being a row this method itself once placed.  A transaction added by hand through the UI is
  # not: TransactionsController permits neither balance nor day_index, and nothing calls #sequence for it,
  # so it carries null in both.  While importing only ever happened into an empty account that could not
  # arise; with an import screen it can, and both nulls are refused below rather than worked around.
  #
  # @return [void]
  def sequence
    previous_transaction = self.account.transactions.where("date <= ?", self.date).order(:date, :day_index).last

    # `|| 0` because a hand-added predecessor has no day_index, and nil + 1 is a NoMethodError.
    # Transaction::ORDER already coalesces the same null for the same reason.
    self.day_index = previous_transaction&.date == self.date ? (previous_transaction.day_index || 0) + 1 : 0

    calculated_balance = previous_balance(previous_transaction) + self.amount

    if self.balance
      # The system's main integrity check, so it says enough to act on: which row failed, what the statement
      # claimed, what the account works out, and the two things usually behind the difference.
      if calculated_balance != self.balance
        raise ImportError, "#{summary} — the statement says the balance is #{self.balance.format}, where " \
                           "the account works out #{calculated_balance.format}.  Check the account's opening " \
                           "balance, and whether this file covers a period already loaded."
      end
    else
      self.balance = calculated_balance
    end
  end

  # A one-line description of this transaction, for the messages an import fails with.  Public because the
  # messages naming a *previous* transaction are built from that transaction rather than from this one.
  #
  # @return [String]
  def summary = "#{date&.to_fs(:short_date)} #{description.to_s.squish} #{amount&.format}"

  private

  # The balance to chain this transaction onto.
  #
  # Both nils here used to pass silently, and the second was the worse of the two: `previous&.balance ||
  # opening_balance` reads as a sensible default, but where the predecessor is real and merely has no balance
  # of its own it restarts the running total from the opening balance as though the account were empty —
  # producing a figure wrong by everything in between, and on a statement carrying no balance of its own,
  # wrong with nothing to catch it.  Neither is a state this can compute through, so both are refused by name.
  #
  # @param [Transaction, nil] previous_transaction
  # @return [Money]
  def previous_balance(previous_transaction)
    if previous_transaction.nil?
      return account.opening_balance if account.opening_balance

      raise ImportError, "#{account.name} has no opening balance, and every balance is calculated from it.  " \
                         "Set one on the account, working back from the oldest row of this statement."
    end

    return previous_transaction.balance if previous_transaction.balance

    raise ImportError, "the transaction before #{summary} (#{previous_transaction.summary}) has no balance " \
                       "of its own, so the running balance cannot be continued from it.  It was added by " \
                       "hand rather than imported."
  end

  # Turns a confirmed name into an unsaved Counterparty, which belongs_to autosave then writes inside the
  # transaction's own save, in the same database transaction.  Autosave does not check whether that write
  # succeeded, so a name the record would reject has to be caught here and left for #counterparty_name_resolved
  # to report — otherwise the row would save with a silently empty counterparty.
  def accept_confirmed_counterparty
    return if @unresolved_counterparty.blank?

    name = @unresolved_counterparty.squish
    return unless confirmed_counterparty_name.to_s.squish.casecmp?(name)
    return if own_account_named?(name)

    candidate = Counterparty.new(name: name)
    return unless candidate.valid?

    self.counterparty = candidate
    @unresolved_counterparty = nil
    @counterparty_created = true
  end

  # Whatever the confirmation did not settle.  Ordered so the reader is told what is actually wrong: a name
  # that could never become a counterparty is refused rather than offered, so that saving again cannot turn
  # into saving in vain.
  def counterparty_name_resolved
    @counterparty_to_confirm = nil
    return if @unresolved_counterparty.blank?

    name = @unresolved_counterparty.squish
    candidate = Counterparty.new(name: name)

    if own_account_named?(name)
      errors.add(:counterparty_name, "#{name.inspect} is one of your own accounts")
    elsif candidate.invalid?
      errors.add(:counterparty_name, "#{name.inspect} #{candidate.errors[:name].first}")
    else
      @counterparty_to_confirm = name
      errors.add(:counterparty_name, "#{name.inspect} is not a counterparty — save again to create it")
    end
  end

  # Counterparty.named has already missed by the time this is asked, so any Account still answering to the
  # name is one of the household's own.  Account names are case-insensitively unique across the whole STI
  # table, which is why such a counterparty cannot be created at all, only refused.
  def own_account_named?(name)
    Account.named(name).exists?
  end
end
