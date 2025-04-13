class CategoryAddDescription < ActiveRecord::Migration[8.0]
  def change
    # Add a description column to the categories table
    add_column :categories, :description, :text
  end
end
