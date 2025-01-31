class AccountAddTypeField < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :type, :string

    remove_foreign_key :transactions, :transactions
    add_reference :transactions, :debitor_previous_trx,  foreign_key: { to_table: :transactions }
    add_reference :transactions, :creditor_previous_trx,  foreign_key: { to_table: :transactions }
  end
end
