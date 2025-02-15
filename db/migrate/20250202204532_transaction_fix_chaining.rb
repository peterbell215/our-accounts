class TransactionFixChaining < ActiveRecord::Migration[8.0]
  def change
    remove_reference :transactions, :previous_trx_id
    remove_reference :transactions, :debitor_previous_trx
    remove_reference :transactions, :creditor_previous_trx
    add_reference :transactions, :next_trx, foreign_key: { to_table: :transactions }
  end
end