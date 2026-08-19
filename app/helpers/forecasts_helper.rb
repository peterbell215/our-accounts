module ForecastsHelper
  # One button in the forecast's month navigation.
  #
  # A step that would leave the range worth forecasting renders as a disabled button rather than a link,
  # so the controls keep their positions — the same arrangement as the transaction list's date navigation,
  # and for the same reason.  The bounds are real: before the first transaction there is nothing to
  # forecast from, and beyond a year ahead the average window holds nothing that has happened.
  #
  # @param [String] label
  # @param [Forecast::Month] forecast
  # @param [Symbol] direction :back or :forward
  # @return [String]
  def forecast_month_link(label, forecast, direction)
    target = direction == :back ? forecast.previous : forecast.next
    stuck = target < forecast.earliest_month || target > forecast.latest_month

    if stuck
      tag.span label, class: "pure-button pure-button-disabled", aria: { disabled: true }
    else
      link_to label, forecast_path(month: target), class: "pure-button"
    end
  end

  # Where a forecast line's workings live.  The uncategorised line has no category, so it has a page of
  # its own rather than one keyed by an id it does not have.
  #
  # @param [Forecast::Line] line
  # @param [Date] month
  # @return [String]
  def forecast_line_path(line, month)
    if line.uncategorised?
      forecast_uncategorised_path(month: month)
    else
      forecast_category_path(line.category, month: month)
    end
  end

  # A money cell, or an em dash where there is deliberately no figure — an excluded category has no
  # prediction, which is a different thing from a prediction of nothing.
  #
  # @param [Money, nil] amount
  # @return [String]
  def forecast_money(amount) = amount.nil? ? "—" : humanized_money_with_symbol(amount)
end
