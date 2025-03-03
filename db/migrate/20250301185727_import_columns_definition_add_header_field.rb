class ImportColumnsDefinitionAddHeaderField < ActiveRecord::Migration[8.0]
  def change
    add_column :import_columns_definitions, :header, :boolean, default: true
  end
end
