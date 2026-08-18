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

  # Blank clears the counterparty.  A name matching none is an error rather than a new Counterparty:
  # counterparty names are already sprawling, because AnalysisImporter derived them from raw statement text,
  # and creating one on a typo would add to that.  Counterparties are created deliberately, on their own
  # screen.
  #
  # A value that already names this transaction's counterparty is left alone rather than resolved again.
  # #counterparty is an Account, and import data or the console can point it at one of the household's own
  # accounts; the cell then renders that account's name, which Counterparty does not contain, so submitting
  # the row — even to change nothing but the category — used to fail on a name the user never typed.
  # Resolving a *changed* name still goes through Counterparty only, so an own account cannot be chosen.
  # @param [String, nil] value
  def counterparty_name=(value)
    @counterparty_name = value
    @unresolved_counterparty = nil

    if value.blank?
      self.counterparty = nil
    elsif !counterparty&.name&.casecmp?(value.squish)
      match = Counterparty.where("LOWER(name) = ?", value.squish.downcase).order(:id).first
      match ? self.counterparty = match : @unresolved_counterparty = value
    end
  end

  # Find if a match for this trx exists using the ImportMatcher class.
  # @return [Transaction]
  def find_match
    match = ImportMatcher.find_match(self)

    if match
      self.import_matcher_id = match.id
      self.counterparty = match.counterparty
      self.category_id = match.category_id
    end
  end

  # Add an imported transaction to the account, taking account of whether other transactions have already been added.

  # @return [void]
  def sequence
    previous_transaction = self.account.transactions.where("date <= ?", self.date).order(:date, :day_index).last
    self.day_index = previous_transaction&.date == self.date ? previous_transaction.day_index + 1 : 0

    calculated_balance = (previous_transaction&.balance || self.account.opening_balance) + self.amount

    if self.balance
      raise ImportError if calculated_balance != self.balance
    else
      self.balance = calculated_balance
    end
  end

  private

  def counterparty_name_resolved
    return if @unresolved_counterparty.blank?

    errors.add(:counterparty_name, "#{@unresolved_counterparty.squish.inspect} is not a counterparty")
  end
end
