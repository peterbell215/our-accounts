# Every transaction the forecast needs, loaded in two queries.
#
# Without this the page would be one query per category per month — thirty categories over a six-month
# window is a hundred and eighty round trips to answer one screen.  Two loads serve the whole thing:
#
# 1. **The window**, over every category at once and the uncategorised bucket with them, spanning the
#    widest lookback any category asks for through to the end of the month being forecast.
# 2. **All history**, restricted to the categories forecast from their regular payments — usually two or
#    three, so a few hundred rows.  Those need every occurrence they can get: an annual insurance premium
#    appears at most once in a six-month window and could never be recognised from it.
#
# Rows are plucked and grouped in Ruby rather than grouped by `strftime('%Y-%m', date)` in SQL.  That
# keeps SQLite's date functions out of the application, costs a few milliseconds on a few thousand rows,
# and follows CounterpartiesController#index, which sorts its derived totals in memory for the same
# reason.  If it ever stops being fast enough the escape hatch is obvious.
#
# This is also the one place in the module that negates an amount — see the note in Forecast.
class Forecast::History
  # One transaction, reduced to what a forecast cares about.  `amount` is a **positive** Money.
  Row = Struct.new(:category_id, :counterparty_id, :description, :date, :amount, keyword_init: true) do
    def month_index = Forecast.month_index(date)
  end

  attr_reader :window_end_index, :earliest_month_index

  # @param [Date] month the first of the month being forecast
  # @param [Date] today
  # @param [Array<Category>] categories every category, so that one pass covers them all
  def initialize(month:, today:, categories:)
    @month_index = Forecast.month_index(month)
    @categories = categories

    # An average looks back over the months before the month being forecast — not the months before
    # today, so that a forecast for March reads the same in June as it did in March, and a month gone by
    # becomes a genuine test of how the forecast did.  But the end is *also* held to the last month that
    # has actually happened: without that, a forecast three months out would average over months that do
    # not exist yet, each contributing nothing and dragging the prediction down by a third.
    @window_end_index = [ @month_index, Forecast.month_index(today) ].min - 1

    earliest = Transaction.minimum(:date)
    @earliest_month_index = earliest && Forecast.month_index(earliest)

    load_window
    load_all_history
  end

  # Windowed rows for one category, or for the uncategorised bucket when given nil.
  #
  # @param [Integer, nil] category_id
  # @return [Array<Row>]
  def rows_for(category_id) = @window.fetch(category_id, [])

  # Every row ever recorded against one category, for regular-payment detection.
  #
  # @param [Integer, nil] category_id
  # @return [Array<Row>]
  def all_rows_for(category_id) = @all_history.fetch(category_id, [])

  # @return [Boolean] whether there is any history at all to forecast from
  def any_transactions? = !@earliest_month_index.nil?

  private
    # The widest lookback in play.  The uncategorised line has no category to carry a setting, so the
    # default is always a candidate.
    def widest_window
      ([ Category::DEFAULT_FORECAST_MONTHS ] + @categories.map(&:forecast_window)).max
    end

    def load_window
      first = Forecast.month_from_index(@window_end_index - widest_window + 1)
      last = Forecast.month_from_index(@month_index).end_of_month

      @window = group(Transaction.spend.where(date: first..last))
    end

    def load_all_history
      ids = @categories.select(&:forecast_regular_payments?).map(&:id)
      @all_history = ids.empty? ? {} : group(Transaction.spend.where(category_id: ids))
    end

    # Pluck rather than instantiate: a few thousand Transaction objects to sum five columns is waste.
    def group(scope)
      rows = scope.pluck(:category_id, :counterparty_id, :description, :date, :amount_pence)

      rows.map { |category_id, counterparty_id, description, date, pence|
        Row.new(category_id: category_id, counterparty_id: counterparty_id, description: description,
                date: date, amount: Money.new(-pence))
      }.group_by(&:category_id)
    end
end
