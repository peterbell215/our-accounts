class RenameImportColumnDefinitionToImportColumnsDefinition < ActiveRecord::Migration[8.0]
  def change
    rename_table :import_column_definitions, :import_columns_definitions
  end
end
