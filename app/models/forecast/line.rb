# One row of the forecast: a category, what it is expected to cost this month, and how much of that has
# already gone.
#
# The division of labour here is the design's one real idea. **`actual` belongs to the line** and is the
# same thing whatever method the category uses — everything spent in the category this month, including
# spending no method predicted. **`remaining` belongs to the strategy**, because how much is still to
# come depends entirely on how the prediction was arrived at: a category predicted from its total
# subtracts what has gone from that total, while a category predicted from its individual payments
# settles them one by one and is unmoved when one of them overshoots.
class Forecast::Line
  attr_reader :category, :label, :method, :strategy, :actual

  # @param [Category, nil] category nil for the uncategorised line
  # @param [String] label
  # @param [Symbol] method
  # @param [Object] strategy one of the four Forecast strategies
  # @param [Money] actual everything spent in this category this month
  def initialize(category:, label:, method:, strategy:, actual:)
    @category = category
    @label = label
    @method = method
    @strategy = strategy
    @actual = actual
  end

  def excluded? = method == :excluded

  # The uncategorised line stands for everything with no category at all, so it has no record behind it
  # and nothing to configure.
  def uncategorised? = category.nil?

  # @return [Money, nil] the whole month's prediction
  def expected = strategy.expected

  # @return [Money, nil] never negative
  def remaining = strategy.remaining(actual)

  # What the month looks like ending at: what has gone, plus what is still expected.
  #
  # @return [Money, nil]
  def projected = excluded? ? nil : actual + remaining

  # How the prediction did, for a month that has finished. Positive means overspent.
  #
  # @return [Money, nil]
  def difference = excluded? ? nil : actual - expected

  # A manual category nobody has given a figure for. The screen has to say so rather than showing zero.
  def awaiting_figure? = method == :manual && !strategy.set?
end
