class TransactionAddImportColumns < ActiveRecord::Migration[8.0]
  def change
    change_table :transactions do |t|
      t.string :description, null: true
      t.string :trx_type, null: true
      t.references :import_matcher
    end
  end
end
