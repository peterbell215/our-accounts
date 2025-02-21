class RemoveNotNullConstraintFromBalancePence < ActiveRecord::Migration[8.0]
  def change
    change_column :transactions, :balance_pence, :integer, null: true, default: nil
  end
end
