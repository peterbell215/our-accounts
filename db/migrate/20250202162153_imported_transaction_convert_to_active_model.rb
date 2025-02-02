class ImportedTransactionConvertToActiveModel < ActiveRecord::Migration[8.0]
  def change
    drop_table :imported_transactions
  end
end