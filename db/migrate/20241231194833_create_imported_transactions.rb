class CreateImportedTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :imported_transactions do |t|
      t.references :import_account, null: false, foreign_key: true
      t.date :date
      t.string :description
      t.string :trx_type
      t.monetize :amount

      t.timestamps
    end
  end
end
