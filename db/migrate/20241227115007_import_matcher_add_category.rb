class ImportMatcherAddCategory < ActiveRecord::Migration[8.0]
  def change
    add_reference :import_matchers, :category, foreign_key: true
  end
end
