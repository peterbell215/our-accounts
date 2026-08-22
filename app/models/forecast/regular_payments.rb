# Predicts a category by recognising the individual payments that make it up.
#
# The right method for Utilities and Subscriptions: a handful of direct debits, each on its own cadence
# and each a known amount, where averaging the category throws away everything worth knowing.  Predicting
# them one at a time is also what lets the month's remaining spend be honest — see Forecast::Payment#remaining.
#
# Detection runs over **all** history rather than the average's window.  A six-month window holds at most
# one occurrence of an annual premium, so it could never reach the two occurrences a cadence needs.  What
# replaces the window is a staleness rule expressed in the payment's own cadence, which is strictly
# better: a monthly payment is allowed two months of silence before it is treated as finished, a
# quarterly one four, an annual one thirteen.  Without it, a subscription cancelled three years ago has a
# spotless monthly cadence and reads as due every month for ever.
class Forecast::RegularPayments
  # The cadences real payments actually use.  A raw median gap of two or five months is noise around one
  # of these rather than a schedule anything is on.
  CADENCES = [ 1, 3, 6, 12 ].freeze

  # One sighting says nothing whatever about a cadence.
  MINIMUM_OCCURRENCES = 2

  # @param [Array<Forecast::History::Row>] rows every row ever recorded against this category
  # @param [Date] month the first of the month being forecast
  def initialize(rows:, month:)
    @rows = rows
    @index = Forecast.month_index(month)
  end

  # @return [Money]
  def expected = payments.select(&:due?).sum(Money.new(0), &:amount)

  # Summed payment by payment, never from the category's total.  `spent` is ignored deliberately: a
  # one-off in this category is real spending and belongs in the month's actual, but it says nothing
  # about which of the recognised payments are still to come.
  #
  # @return [Money]
  def remaining(_spent) = payments.sum(Money.new(0), &:remaining)

  # The payments recognised and still live, in the order they read best — due first, then by name.
  #
  # @return [Array<Forecast::Payment>]
  def payments
    @payments ||= groups.filter_map { |label, rows| payment_for(label, rows) }
                        .sort_by { |payment| [ payment.due? ? 0 : 1, payment.label ] }
  end

  # Groups that repeat but too erratically to put a cadence on.  Reported on the workings page rather
  # than dropped in silence, because silence here is money vanishing from the total with no trace.
  #
  # @return [Array<String>]
  def irregular
    @irregular ||= groups.filter_map { |label, rows| label if erratic?(rows) }.sort
  end

  private
    # A payee is its counterparty where it has one, and its exact description where it does not — plenty
    # of direct debits never acquired a counterparty.
    #
    # The known weakness: a payee that gained a counterparty part-way through its history splits into two
    # groups, each of which may fall below the two occurrences it needs, and the series is then not
    # recognised at all.  It fails visibly — nothing appears on the workings page — and merging the two
    # counterparties reunites it.
    def groups
      @groups ||= @rows.group_by { |row| row.counterparty_id || row.description }
                       .transform_keys { |key| key.is_a?(Integer) ? counterparties.fetch(key).name : key }
    end

    # One load for every counterparty in the category, rather than one per recognised payment.
    def counterparties
      @counterparties ||= Account.where(id: @rows.filter_map(&:counterparty_id).uniq).index_by(&:id)
    end

    # Everything strictly before the month being forecast, totalled by month.  Occurrences *after* it are
    # excluded as well as those within it, so that forecasting a month gone by uses only what was known
    # at the time and stays a fair test of the method.
    def evidence(rows)
      rows.reject { |row| row.month_index >= @index }
          .group_by(&:month_index)
          .transform_values { |month_rows| month_rows.sum(Money.new(0), &:amount) }
          .sort
    end

    def erratic?(rows)
      months = evidence(rows)
      return false if months.count < MINIMUM_OCCURRENCES

      median_gap(months.map(&:first)) > CADENCES.max
    end

    def payment_for(label, rows)
      months = evidence(rows)
      return nil if months.count < MINIMUM_OCCURRENCES

      raw = median_gap(months.map(&:first))
      return nil if raw > CADENCES.max

      cadence = CADENCES.min_by { |candidate| (candidate - raw).abs }

      # The amount is the **most recent** occurrence, not an average of them.  This looks lazy and is
      # not: the whole reason to predict a category this way rather than by its average is that a direct
      # debit steps up, and the new figure is what next month will cost.  Averaging the last few lags
      # precisely the change the method exists to catch.  The price is a genuinely variable bill, where
      # the answer is to forecast that category by its average instead — which the README says.
      last_index, amount = months.last
      silence = @index - last_index
      # Finished, not merely quiet.  A cadence's worth of silence plus a month's grace.
      return nil if silence > cadence + 1

      landed = rows.select { |row| row.month_index == @index }

      Forecast::Payment.new(
        label: label,
        counterparty: counterparty_for(rows),
        amount: amount,
        cadence: cadence,
        last_seen: rows.select { |row| row.month_index == last_index }.map(&:date).max,
        due: (silence % cadence).zero?,
        landed_on: landed.map(&:date).min,
        landed_amount: landed.sum(Money.new(0), &:amount)
      )
    end

    def counterparty_for(rows)
      id = rows.filter_map(&:counterparty_id).first
      id && counterparties[id]
    end

    def median_gap(indices)
      gaps = indices.each_cons(2).map { |before, after| after - before }
      sorted = gaps.sort
      middle = sorted.size / 2

      sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
    end
end
