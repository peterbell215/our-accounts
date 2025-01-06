class ImportededTransaction < ActiveRecord::Migration[8.0]
  def change
    add_column :imported_transactions, :balance_pence, :integer
    add_column :imported_transactions, :balance_currency, :string
  end
end
