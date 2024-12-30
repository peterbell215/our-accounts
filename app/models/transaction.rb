class Transaction < ApplicationRecord
  belongs_to :creditor
  belongs_to :debitor

  validates :date, presence: true
  validates :amount, presence: true
  validates :creditor, presence: true
  validates :debitor, presence: true

  monetize :amount_pence


  def self.import(csv, account)
    import_matchers = account.import_matchers
    import_column_definitions = account.import_column_definitions

    CSV.foreach(csv.path, headers: true) do |row|
      check_sortcode_and_account(account, import_column_definitions, row)

      transaction = Transaction.new
      transaction.date = Date.strptime(row[import_matcher.date_column], import_matcher.date_format)



      if import_column_definitions.debit_column && import_column_definitions.credit_column

      end
      transaction.amount = Money.new(row[import_matcher.amount_column].to_f * 100, import_matcher.account.currency)
      transaction.creditor = import_matcher.account
      transaction.debitor = import_matcher.account




      transaction.save
    end
  end

  private

  def self.check_sortcode_and_account(account, import_column_definitions, row)
    if import_column_definitions.account_number_column && import_column_definitions.sortcode_column
      account_number = row[import_column_definitions.account_number_column]
      sortcode = row[import_column_definitions.sortcode_column]

      account.account_number == account_number && account.sortcode == sortcode
    end
  end
end
