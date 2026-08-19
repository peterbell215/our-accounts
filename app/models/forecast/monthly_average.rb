# Predicts a category from the mean of what it cost over recent complete months.
#
# The right method for the categories that are steady in aggregate and unpredictable one transaction at
# a time — Food, Car, the weekly shop.  There is no pattern in the individual rows worth chasing, and
# the average of the last few months is as good a guess as anything more elaborate.
#
# The month being forecast is deliberately left out of its own window, whether or not it has finished:
# including a part-spent month would drag every prediction down by however far through it we are.
class Forecast::MonthlyAverage
  # @param [Array<Forecast::History::Row>] rows windowed rows for one category, or the uncategorised bucket
  # @param [Forecast::History] history
  # @param [Integer] months the lookback
  def initialize(rows:, history:, months:)
    @rows = rows
    @history = history
    @months = months
  end

  # @return [Money]
  def expected
    return Money.new(0) if divisor.zero?

    # Integer division drops at most a penny per category, which is immaterial in a prediction.  Do not
    # "fix" this with a float: money in this application is always integer pence.
    Money.new(window_total.cents / divisor)
  end

  # @param [Money] spent this month so far
  # @return [Money]
  def remaining(spent) = [ expected - spent, Money.new(0) ].max

  # The months the average is taken over, each with what was actually spent, for the workings page.  The
  # zeroes are the point of showing it: a category that reads low usually has months in here it did not
  # exist for.
  #
  # @return [Array<Array(Date, Money)>]
  def window_months
    window_indices.map { |index| [ Forecast.month_from_index(index), totals_by_month.fetch(index, Money.new(0)) ] }
  end

  # How many months the total is divided by.
  #
  # This is the whole question, and it is settled on the **dataset's** history rather than the
  # category's.  Dividing by the months the category itself has existed for would make a category with
  # one £600 transaction four months ago predict £600 every month for ever.  Dividing by the months the
  # records cover means a month in which the household genuinely spent nothing on Food did happen, and
  # does pull the average down — which is what an average of recent months is supposed to mean.
  #
  # The cost is a category younger than the window, which is averaged over months of zeroes and reads
  # low.  That is what `Category#forecast_months` is for, and why the months are printed on the workings
  # page with the zeroes visible: the remedy is only reachable if the cause is.
  #
  # @return [Integer]
  def divisor = covered_indices.count

  # @return [Integer] months in the window that predate the records entirely
  def uncovered = window_indices.count - divisor

  private
    def window_indices
      finish = @history.window_end_index
      ((finish - @months + 1)..finish).to_a
    end

    def covered_indices
      earliest = @history.earliest_month_index
      return [] if earliest.nil?

      window_indices.select { |index| index >= earliest }
    end

    def totals_by_month
      @totals_by_month ||= @rows.group_by(&:month_index).transform_values { |rows| rows.sum(Money.new(0), &:amount) }
    end

    def window_total
      window_indices.sum(Money.new(0)) { |index| totals_by_month.fetch(index, Money.new(0)) }
    end
end
