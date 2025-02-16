module Balances
  extend ActiveSupport::Concern

  class_methods do
    @balances = true
  end

  included do
    validates :opening_balance, presence: true

    # Add an imported transaction to the account, taking account of whether other transactions have already been added.
    def add_transaction(imported_transaction)
      match = ImportMatcher.find_match(imported_transaction)

      trx = Transaction.new(account_id: self.id,
                            amount: imported_transaction.amount,
                            date: imported_transaction.date,
                            other_party: match.other_party,
                            category_id: match.category_id)

      previous_transaction = self.transactions.where("date <= ?", trx.date).order(:day_index).first
      trx.day_index = previous_transaction&.date == trx.date ? previous_transaction.day_index + 1 : 0

      trx.balance = (previous_transaction&.balance || trx.account.opening_balance) + trx.amount

      raise ImportError if imported_transaction.balance && imported_transaction.balance!=trx.balance

      trx.save!
      trx
    end
  end
end
