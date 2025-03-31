class ImportColumnsDefinitionAddReversed < ActiveRecord::Migration[8.0]
  def change
    add_column :import_columns_definitions, :reversed, :boolean, default: false
  end
end
