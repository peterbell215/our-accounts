class RenameTransactionTypeColumnToTrxTypeColumn < ActiveRecord::Migration[8.0]
  def change
    rename_column :import_columns_definitions, :transaction_type_column, :trx_type_column
  end
end
