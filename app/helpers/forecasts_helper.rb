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

  # Why one payee is, or is not, part of the forecast, in a sentence.
  #
  # The words live here rather than on Forecast::Payment because they are screen prose and because they
  # need dates formatted, which is a helper's job everywhere else in this application.  Every reason is
  # said out loud on both screens that show a payment: a payee dropped in silence is money missing from
  # the total with nothing to explain it, which is the failure this whole strategy is arranged to avoid.
  #
  # @param [Forecast::Payment] payment
  # @return [String]
  def payment_reason(payment)
    case payment.status
    when :forecast   then payment.set_by_hand? ? "Yes — at the frequency you set" : "Yes"
    when :suppressed then "No — you have said it is not a regular payment"
    when :erratic    then "No — it repeats too erratically to put a frequency on"
    when :finished   then "No — nothing since #{short_date payment.last_seen}"
    when :seen_once  then "No — seen only once before this month, on #{short_date payment.last_seen}; " \
                          "set a frequency to forecast it anyway"
    when :unseen     then unseen_reason(payment)
    end
  end

  # One payee's frequency, and whether the reader set it or the history did.
  #
  # @param [Forecast::Payment] payment
  # @return [String]
  def payment_cadence(payment)
    return "—" if payment.cadence_label.nil?
    return payment.cadence_label unless payment.set_by_hand?
    return "#{payment.cadence_label} (set by hand)" unless payment.overrules_history?

    # Worth spelling out: the reader is entitled to see the guess they overruled, and to notice where the
    # history has since caught up with them and the ruling is doing nothing.
    "#{payment.cadence_label} (set by hand; the history says " \
      "#{Forecast::CADENCE_LABELS.fetch(payment.inferred_cadence).downcase})"
  end

  # The choices for one payee's frequency: leave it to the history, name it, or rule it out.
  #
  # @return [Array<Array>]
  def payment_schedule_options
    [ [ "Work it out from the history", PaymentSchedule::WORK_IT_OUT ] ] +
      Forecast::CADENCE_LABELS.map { |months, label| [ label, months ] } +
      [ [ "Not a regular payment", PaymentSchedule::NOT_REGULAR ] ]
  end

  # A money cell, or an em dash where there is deliberately no figure — an excluded category has no
  # prediction, which is a different thing from a prediction of nothing.
  #
  # @param [Money, nil] amount
  # @return [String]
  def forecast_money(amount) = amount.nil? ? "—" : humanized_money_with_symbol(amount)

  private
    # Nothing in a completed month covers two situations, and what the reader should do differs.
    #
    # A payee seen only within the month being forecast cannot be rescued by any frequency, because the
    # amount is taken from a month that has finished — it joins the forecast next month either way, and
    # it has already gone out, so nothing is owed for it now.
    #
    # No history at all means a frequency set against a payee that has since gone: its transactions
    # recategorised, or its counterparty merged away.  The ruling is doing nothing and should be
    # withdrawn, which is said plainly rather than left as a puzzle.
    # A nil amount is how "no history at all" tells itself apart: the amount is the most recent payment,
    # so a payee with none has nothing to show and Forecast::RegularPayments leaves it unset rather than
    # putting £0.00 there.
    def unseen_reason(payment)
      return "No — first seen this month, so it joins the forecast next month" unless payment.amount.nil?

      "No — nothing in this category is paid to it any more, so this setting does nothing.  " \
        "Choose \"work it out from the history\" to clear it."
    end
end
