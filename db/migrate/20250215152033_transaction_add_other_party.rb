class TransactionAddOtherParty < ActiveRecord::Migration[8.0]
  def change
    add_reference :transactions, :other_party, foreign_key: { to_table: :accounts }
  end
end
