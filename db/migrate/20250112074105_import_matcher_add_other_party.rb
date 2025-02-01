class ImportMatcherAddOtherParty < ActiveRecord::Migration[8.0]
  def change
    add_reference :import_matchers, :other_party, null: false, foreign_key: { to_table: :accounts }, index: true
    change_column_null :import_matchers, :category_id, false
  end
end
