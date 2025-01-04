class ImportColumnsDefinition < ActiveRecord::Migration[8.0]
  def change
    create_table :import_column_definitions do |t|
      t.references :account, null: false
      t.integer :date_column, null: false
      t.string :date_format, null: false
      t.integer :transaction_type_column
      t.integer :sortcode_column
      t.integer :account_number_column
      t.integer :other_party_column
      t.integer :amount_column
      t.integer :debit_column
      t.integer :credit_column
      t.integer :balance_column

      t.timestamps
    end

    remove_columns :import_matchers, :transaction_type_column, :sortcode_column, :account_number_column,
                                     :other_party_column, :amount_column, :debit_column, :credit_column, :balance_column
    add_reference :import_matchers, :import_column_definition, null: false, foreign_key: true
    add_column :import_matchers, :other_party, :string, null: false
    add_column :import_matchers, :other_party_is_regex, :boolean, default: false, null: false
  end
end
