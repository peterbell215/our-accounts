class CreateManualForecasts < ActiveRecord::Migration[8.1]
  def change
    # A figure the user has entered by hand for one category in one month, for the categories too lumpy
    # to infer anything from.  The only thing the forecasting module stores beyond configuration.
    create_table :manual_forecasts do |t|
      t.references :category, null: false, foreign_key: true, index: false
      # `index: false` above: the composite index below leads on category_id and covers it.
      t.date :month, null: false
      # money-rails' helper, so these match every other money column in the schema.
      t.monetize :amount

      t.timestamps
    end

    # One figure per category per month.  `ManualForecast` normalises `month` to the first of the month,
    # which is what makes this index mean what it says.
    add_index :manual_forecasts, [ :category_id, :month ], unique: true
  end
end
