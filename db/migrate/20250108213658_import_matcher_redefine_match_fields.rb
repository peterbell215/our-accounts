class ImportMatcherRedefineMatchFields < ActiveRecord::Migration[8.0]
  def change
    add_column :import_matchers, :trx_type, :string
    remove_reference :import_matchers, :import_column_definition
    rename_column :import_matchers, :other_party, :description
    rename_column :import_matchers, :other_party_is_regex, :description_is_regex
  end
end
