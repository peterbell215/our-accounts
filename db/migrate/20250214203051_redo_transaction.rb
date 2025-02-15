class RedoTransaction < ActiveRecord::Migration[8.0]
  def change
    drop_table :transactions

    create_table :transactions do |t|
      t.references :account
      t.references :category

      t.date :date, null: false
      t.monetize :amount, null: false
      t.monetize :balance

      t.integer :sequence
    end
  end
end