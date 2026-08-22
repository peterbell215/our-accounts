class CategoryAddForecastMethod < ActiveRecord::Migration[8.1]
  def change
    # How this category's spend is predicted.  Stored as a string rather than an integer: it is read in
    # one place, there are a few dozen rows, and the value is legible when the SQLite file is opened
    # directly.  The default backfills every category the analysis import already created, which is the
    # honest generic answer for one nobody has configured.
    add_column :categories, :forecast_method, :string, null: false, default: "monthly_average"

    # How many complete months the average looks back over.  Null means the default of six.
    add_column :categories, :forecast_months, :integer
  end
end
