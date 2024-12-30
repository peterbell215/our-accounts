class ImportMatcher < ActiveRecord::Migration[8.0]
  def change
    create_table :import_matchers do |t|
      t.references :account, null: false, foreign_key: true, index: true
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
  end
end
