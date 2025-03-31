# A transaction represents
class Transaction < ApplicationRecord
  belongs_to :account, optional: false

  belongs_to :category, optional: true
  belongs_to :other_party, class_name: "Account", foreign_key: "other_party_id", optional: true
  belongs_to :import_matcher, optional: true

  validates :date, presence: true
  validates :amount, presence: true

  monetize :amount_pence
  monetize :balance_pence, allow_nil: true

  # Find if a match for this trx exists using the ImportMatcher class.
  # @return [Transaction]
  def find_match
    match = ImportMatcher.find_match(self)

    if match
      self.import_matcher_id = match.id
      self.other_party = match.other_party
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
end
