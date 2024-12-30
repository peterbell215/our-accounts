class ImportMatcherRemoveDate < ActiveRecord::Migration[8.0]
  def change
    remove_columns :import_matchers, :date_column, :date_format
  end
end
