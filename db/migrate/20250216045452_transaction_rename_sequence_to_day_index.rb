class TransactionRenameSequenceToDayIndex < ActiveRecord::Migration[8.0]
  def change
    rename_column :transactions, :sequence, :day_index
  end
end
