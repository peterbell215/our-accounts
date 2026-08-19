# A category the reader predicts themselves.
#
# Holidays is the standing example: the spending is real and often large, but nothing in its history
# says anything about what next month holds.  Rather than produce a confident number from noise, the
# forecast asks.
class Forecast::ManualAmount
  # @param [ManualForecast, nil] record the figure for this category and month, where one has been set
  def initialize(record:)
    @record = record
  end

  attr_reader :record

  # Whether anybody has actually said.  The screen leans on this: a category awaiting a figure must read
  # "not set" rather than "£0.00", which would claim a prediction of nothing was made deliberately.
  def set? = !@record.nil?

  # @return [Money]
  def expected = set? ? @record.amount : Money.new(0)

  # @param [Money] spent this month so far
  # @return [Money]
  def remaining(spent) = set? ? [ expected - spent, Money.new(0) ].max : Money.new(0)
end
