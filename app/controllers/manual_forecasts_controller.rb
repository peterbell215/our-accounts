# The figure a reader enters by hand for a category the application will not guess at.
#
# One action, because there is only one thing to do: say what this category will cost this month, change
# what you said, or take it back.  An upsert rather than the usual new/create/edit/update quartet — the
# record is a single number against a category and a month, and five routes and two more screens would
# be machinery around it rather than help with it.
class ManualForecastsController < ApplicationController
  # POST /forecast/categories/:id/manual
  def update
    @category = Category.find(params[:id])
    month = requested_month
    manual_forecast = ManualForecast.find_or_initialize_by(category: @category, month: month)

    # Emptying the field is how a prediction is withdrawn.  Saving a blank as zero would be a different
    # statement — "nothing will be spent" rather than "I have not said" — and the screen distinguishes them.
    if submitted_amount.blank?
      manual_forecast.destroy if manual_forecast.persisted?
      return redirect_to forecast_category_path(@category, month: month), notice: "Prediction cleared."
    end

    if manual_forecast.update(amount: submitted_amount)
      redirect_to forecast_category_path(@category, month: month), notice: "Prediction saved."
    else
      @manual_forecast = manual_forecast
      @forecast = Forecast::Month.new(month: month)
      @line = @forecast.line_for(@category)

      render "forecasts/category", status: :unprocessable_entity
    end
  end

  private
    def submitted_amount = params.dig(:manual_forecast, :amount)

    # @return [Date]
    def requested_month
      Date.parse(params[:month].to_s).beginning_of_month
    rescue Date::Error
      Date.current.beginning_of_month
    end
end
