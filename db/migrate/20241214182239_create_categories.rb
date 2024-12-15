class CreateCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :categories do |t|
      t.string :name

      t.timestamps
    end

    add_reference :transactions, :category, null: true, foreign_key: true
  end
end
