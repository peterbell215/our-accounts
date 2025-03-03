class ImportColumnDefinitionChangeColumnType < ActiveRecord::Migration[8.0]
  def up
    change_column :import_columns_definitions, :date_column, :string
    change_column :import_columns_definitions, :trx_type_column, :string
    change_column :import_columns_definitions, :sortcode_column, :string
    change_column :import_columns_definitions, :account_number_column, :string
    change_column :import_columns_definitions, :other_party_column, :string
    change_column :import_columns_definitions, :debit_column, :string
    change_column :import_columns_definitions, :credit_column, :string
    change_column :import_columns_definitions, :balance_column, :string
  end

  def down
    change_column :import_columns_definitions, :date_column, :integer
    change_column :import_columns_definitions, :trx_type_column, :integer
    change_column :import_columns_definitions, :sortcode_column, :integer
    change_column :import_columns_definitions, :account_number_column, :integer
    change_column :import_columns_definitions, :other_party_column, :integer
    change_column :import_columns_definitions, :debit_column, :integer
    change_column :import_columns_definitions, :credit_column, :integer
    change_column :import_columns_definitions, :balance_column, :integer
  end
end
