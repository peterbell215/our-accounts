# This class provides a method #match to check if an ImportedTransaction matches the criteria defined
# by ImportMatcher.  An ImportMatcher is always associated with a specific account.  It understands
# how a specific transaction, say a DD from Octopus Energy will look in the Lloyds Account import.
class ImportMatcher < ApplicationRecord
  belongs_to :account
  # Optional: a rule's job is to assign a category.  Naming the counterparty is a bonus, and for a one-off
  # or an unidentifiable vendor there is no name to give — the same reason Transaction#counterparty is
  # optional.
  belongs_to :counterparty, class_name: "Account", inverse_of: :counterparty_matchers, optional: true
  belongs_to :category

  # The order #find_match walks the rules in, and therefore which rule wins when two of them match.  A
  # literal description is the more specific claim, so it beats a regex; false sorts before true.  Without
  # this the winner is whatever order the database happens to return, which only went unnoticed because
  # every rule AnalysisImporter derives is a literal.
  scope :in_match_order, -> { order(:description_is_regex, :id) }

  # #match reads a nil trx_type as "any transaction type", and compares any other value for equality.  A
  # form submits "" for a field left empty, and a rule requiring an empty transaction type would never fire,
  # so blank has to become nil rather than being stored as typed.
  normalizes :trx_type, with: ->(trx_type) { trx_type.presence }

  # A rule with a blank description is never what was meant: as a literal it is a rule no transaction can
  # equal, and as a regex it compiles to //, which matches every description and so quietly claims every
  # transaction no other rule caught.  The form makes both reachable, so refuse them here.
  validates :description, presence: true, uniqueness: { scope: [ :account_id, :trx_type ] }

  validate :description_compiles, if: :description_is_regex?

  # Provided with an `ImportedTransaction` object, try and find a match using the matchers held in the database.
  #
  # `matchers` lets a caller with many transactions to categorise load the rules once instead of once per
  # row.  FileImporter does: this used to issue a query per row that instantiated every rule the account has,
  # which against a real statement is a few thousand queries and the better part of a million objects — far
  # more than the balance lookup the (account_id, date) index was added for, and the reason an import could
  # not be run inside a web request.
  #
  # Passing a preloaded list cannot leak a rule across accounts, because #match re-checks account_id itself.
  # It does have to be `in_match_order`, since that is what makes a literal description beat a regex.
  #
  # @param [ImportedTransaction] imported_transaction
  # @param [Enumerable<ImportMatcher>, nil] matchers the rules to consider; loaded from the transaction's
  #                                                  own account when not given
  # @return [nil|ImportMatcher] returns either nil if no match can be found or a reference to the first
  #                                successful match
  def self.find_match(imported_transaction, matchers = nil)
    matchers ||= ImportMatcher.where(account_id: imported_transaction.account_id).in_match_order

    matchers.each do |matcher|
      return matcher if matcher.match(imported_transaction)
    end

    nil
  end

  # Tests whether the ```imported_transaction``` matches the criteria defined in the ```ImportMatcher```
  # @param [ImportedTransaction] imported_transaction
  def match(imported_transaction)
    return false if self.account_id != imported_transaction.account_id
    return false if self.trx_type != nil && self.trx_type != imported_transaction.trx_type

    if self.description_is_regex
      return false if Regexp.new(self.description) !~ imported_transaction.description
    else
      return false if self.description != imported_transaction.description
    end

    true
  end

  private

  # #match compiles the pattern on every comparison, so an unparseable one would raise part-way through an
  # import of a few thousand rows rather than when the rule was written.
  def description_compiles
    Regexp.new(description.to_s)
  rescue RegexpError => e
    errors.add(:description, "is not a valid regular expression (#{e.message})")
  end
end
