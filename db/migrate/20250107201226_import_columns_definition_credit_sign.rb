class ImportColumnsDefinitionCreditSign < ActiveRecord::Migration[8.0]
  def change
    add_column :import_columns_definitions, :credit_sign, :integer, default: +1
  end
end
