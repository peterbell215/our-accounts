class ImportedTransaction < ApplicationRecord
  belongs_to :import_accounts, class_name: "Account", foreign_key: :import_account_id

  monetize :amount_pence, :balance_pence
end
