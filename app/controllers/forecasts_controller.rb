# The forecast screen and the workings behind each of its lines.  Read-only: nothing here writes, and
# the whole thing is recomputed from the transactions on every request.
class ForecastsController < ApplicationController
  # GET /forecast
  def show
    @forecast = Forecast::Month.new(month: requested_month)
  end

  # GET /forecast/categories/:id
  def category
    @category = Category.find(params[:id])
    @forecast = Forecast::Month.new(month: requested_month)
    @line = @forecast.line_for(@category)

    render :category
  end

  # GET /forecast/uncategorised
  def uncategorised
    @forecast = Forecast::Month.new(month: requested_month)
    @line = @forecast.uncategorised_line

    render :category
  end

  private
    # The month asked for, as its first day.  Anything unreadable falls back to this month rather than
    # raising: a mistyped query string should show the reader a page, not a 500.  Following
    # TransactionPage#coerce_date, which takes the same view of a date arriving as a parameter.
    #
    # @return [Date]
    def requested_month
      clamp(parse_month(params[:month]) || Date.current)
    end

    # @return [Date, nil]
    def parse_month(value)
      return nil if value.blank?

      # "2026-03" as well as a full date, since a month is what the screen is about.
      Date.parse(value.to_s.length == 7 ? "#{value}-01" : value.to_s).beginning_of_month
    rescue Date::Error
      nil
    end

    # Held to the same bounds the navigation buttons show, so that a hand-edited URL cannot strand the
    # reader somewhere the buttons would not have taken them.
    def clamp(month)
      month.beginning_of_month.clamp(Forecast::Month.earliest_month, Forecast::Month.latest_month)
    end
end
