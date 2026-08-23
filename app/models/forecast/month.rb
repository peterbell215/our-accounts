# A whole calendar month's forecast: one line per category, plus the uncategorised line, and the totals.
#
# `today` is an explicit argument rather than being read from the clock inside. That is what lets every
# spec state the situation it is testing — "it is the 10th, and we are forecasting this month" — without
# freezing time, and it is the only reason the suite needs no clock stubbing at all.
class Forecast::Month
  # Everything with no category at all, which on real data is about a third of transactions. Left out,
  # the headline total would be a third short with nothing on the page to say so, so it gets a line of
  # its own — predicted by average, because unclassified spending has no structure to exploit.
  UNCATEGORISED_LABEL = "Uncategorised".freeze

  # How far ahead the screen will go. Beyond a year the average window holds nothing that has happened
  # and the figure would be fiction.
  FORWARD_LIMIT = 12

  # The bounds the month navigation is held within, so that a disabled button means there is genuinely
  # nothing that way rather than being decoration — and so that a hand-edited URL cannot strand the
  # reader somewhere the buttons would not have taken them.  Class methods because the controller needs
  # them to clamp a parameter before it has decided which month to build.
  #
  # @param [Date] today
  # @return [Date]
  def self.earliest_month(today = Date.current)
    earliest = Transaction.minimum(:date)

    earliest ? earliest.beginning_of_month : today.beginning_of_month
  end

  # Beyond a year ahead the average window holds nothing that has happened and the figure is fiction.
  #
  # @param [Date] today
  # @return [Date]
  def self.latest_month(today = Date.current) = today.beginning_of_month >> FORWARD_LIMIT

  attr_reader :month, :today

  # @param [Date] month any date within the month to forecast
  # @param [Date] today
  def initialize(month:, today: Date.current)
    @month = month.beginning_of_month
    @today = today
    @categories = Category.order(:name).to_a
    @history = Forecast::History.new(month: @month, today: @today, categories: @categories)
    @manual = ManualForecast.where(month: @month).index_by(&:category_id)
    @schedules = load_schedules
  end

  # @return [Array<Forecast::Line>] categories by name, then the uncategorised line
  def lines
    @lines ||= @categories.map { |category| line_for_category(category) } << uncategorised_line
  end

  # @param [Category] category
  # @return [Forecast::Line, nil]
  def line_for(category) = lines.find { |line| line.category == category }

  def uncategorised_line
    @uncategorised_line ||= build_line(category: nil, label: UNCATEGORISED_LABEL, method: :monthly_average,
                                       months: Category::DEFAULT_FORECAST_MONTHS)
  end

  # Totals skip the excluded lines entirely rather than adding their nils as zero.
  def expected = total(&:expected)
  def actual = total(&:actual)
  def remaining = total(&:remaining)
  def projected = total(&:projected)

  # Categories forecast by hand that nobody has given a figure for this month. Reported above the table:
  # this is much the likeliest way for the total to be quietly too small.
  #
  # @return [Array<Forecast::Line>]
  def awaiting_figures = lines.select(&:awaiting_figure?)

  # @return [Array<Forecast::Line>]
  def excluded_lines = lines.select(&:excluded?)

  def previous = @month.prev_month
  def next = @month.next_month

  def past? = @month.end_of_month < @today
  def future? = @month > @today
  def current? = !past? && !future?

  def any_transactions? = @history.any_transactions?

  def earliest_month = self.class.earliest_month(@today)
  def latest_month = self.class.latest_month(@today)

  # What has actually gone through one line this month.  The forecast's other half is knowing what has
  # already happened, and a total alone does not let the reader check it — so the workings page lists
  # the rows.  A separate query rather than reusing the loaded history, because these want to be real
  # Transactions with their counterparties, not the five plucked columns the arithmetic needs.
  #
  # @param [Forecast::Line] line
  # @return [ActiveRecord::Relation]
  def transactions_for(line)
    Transaction.spend
               .where(category_id: line.category&.id, date: @month..@month.end_of_month)
               .includes(:counterparty)
               .newest_first
  end

  private
    # The frequencies the reader has set by hand, for the whole page in one query rather than one per
    # category — the same rule Forecast::History follows and for the same reason.  Only the categories
    # forecast from their payments can have any, which is also all History loads full history for.
    def load_schedules
      ids = @categories.select(&:forecast_regular_payments?).map(&:id)

      ids.empty? ? {} : PaymentSchedule.where(category_id: ids).group_by(&:category_id)
    end

    def line_for_category(category)
      build_line(category: category, label: category.name,
                 method: category.forecast_method.to_sym, months: category.forecast_window)
    end

    def build_line(category:, label:, method:, months:)
      id = category&.id
      rows = @history.rows_for(id)

      Forecast::Line.new(category: category, label: label, method: method, actual: spent_in_month(rows),
                         strategy: strategy_for(method, category, rows, months))
    end

    def strategy_for(method, category, rows, months)
      case method
      when :monthly_average  then Forecast::MonthlyAverage.new(rows: rows, history: @history, months: months)
      when :regular_payments then Forecast::RegularPayments.new(rows: @history.all_rows_for(category.id),
                                                                month: @month,
                                                                schedules: @schedules.fetch(category.id, []))
      when :manual           then Forecast::ManualAmount.new(record: @manual[category.id])
      when :excluded         then Forecast::Excluded.new
      else raise ArgumentError, "unknown forecast method #{method.inspect}"
      end
    end

    def spent_in_month(rows)
      index = Forecast.month_index(@month)
      rows.select { |row| row.month_index == index }.sum(Money.new(0), &:amount)
    end

    def total
      lines.reject(&:excluded?).sum(Money.new(0)) { |line| yield(line) }
    end
end
