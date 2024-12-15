class AddAccountDetails < ActiveRecord::Migration[8.0]
  def change
    change_table :accounts do |t|
      t.string :account_number
      t.string :sortcode
      t.date :opening_date
      t.monetize :opening_balance, null: false
    end
  end
end
