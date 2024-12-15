class AddBalanceToAccount < ActiveRecord::Migration[8.0]
  def change
    change_table :transactions do |t|
      t.references :previous_trx, null: false, foreign_key: { to_table: :transactions }, index: true
      t.monetize :balance
    end
  end
end
