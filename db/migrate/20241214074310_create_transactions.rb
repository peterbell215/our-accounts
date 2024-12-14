class CreateTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :transactions do |t|
      t.date :date
      t.monetize :amount
      t.references :creditor, null: false, foreign_key: { to_table: :accounts }, index: true
      t.references :debitor, null: false, foreign_key: { to_table: :accounts }, index: true

      t.timestamps
    end
  end
end
