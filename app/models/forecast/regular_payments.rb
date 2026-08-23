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
#
# **Every payee produces a candidate, not only the ones that pass.**  Three separate rules can keep a
# payee out of the forecast, and each of them is sometimes wrong, so each one has to be visible and each
# one has to be answerable — which is what PaymentSchedule is for.  Money that vanishes from the total
# with nothing on screen to say why is the one outcome this class is written to avoid.
class Forecast::RegularPayments
  # The cadences real payments actually use, from the map that also names them.  A raw median gap of two
  # or five months is noise around one of these rather than a schedule anything is on.
  CADENCES = Forecast::CADENCE_LABELS.keys.freeze

  # One sighting says nothing whatever about a cadence — unless the reader supplies the cadence, which
  # is exactly the gap PaymentSchedule fills.
  MINIMUM_OCCURRENCES = 2

  # @param [Array<Forecast::History::Row>] rows every row ever recorded against this category
  # @param [Date] month the first of the month being forecast
  # @param [Array<PaymentSchedule>] schedules the frequencies the reader has set by hand in this category
  def initialize(rows:, month:, schedules: [])
    @rows = rows
    @index = Forecast.month_index(month)
    @schedules = schedules.index_by(&:payee_key)
  end

  # @return [Money]
  def expected = payments.select(&:due?).sum(Money.new(0), &:amount)

  # Summed payment by payment, never from the category's total.  `spent` is ignored deliberately: a
  # one-off in this category is real spending and belongs in the month's actual, but it says nothing
  # about which of the recognised payments are still to come.
  #
  # @return [Money]
  def remaining(_spent) = payments.sum(Money.new(0), &:remaining)

  # The payments recognised and still live — the ones the forecast is actually made of.
  #
  # @return [Array<Forecast::Payment>]
  def payments = candidates.select(&:forecast?)

  # Every payee in the category, in the order they read best: the forecast ones first, due before not
  # due, then everything left out grouped by why — each carrying the reason it was left out.
  #
  # Over the payees the reader has *ruled on* as well as the ones with history, and those are not the
  # same set.  A ruling outlives its payee: recategorise its transactions, or merge its counterparty
  # away, and the row is still there, predicting nothing and — if this iterated the history alone —
  # appearing on no screen, so the only place able to withdraw it could not show it.
  #
  # @return [Array<Forecast::Payment>]
  def candidates
    @candidates ||= payee_keys.map { |key| candidate_for(key, groups.fetch(key, [])) }
                              .sort_by { |payment|
                                [ payment.status_order, payment.due? ? 0 : 1, payment.label ]
                              }
  end

  # Groups that repeat but too erratically to put a cadence on.
  #
  # @return [Array<String>]
  def irregular = candidates.select { |payment| payment.status == :erratic }.map(&:label).sort

  private
    # A payee is its counterparty where it has one, and its exact description where it does not — plenty
    # of direct debits never acquired a counterparty.  The key is kept raw rather than resolved to a name
    # here, because it is also how a PaymentSchedule names the payee it rules on.
    #
    # The known weakness: a payee that gained a counterparty part-way through its history splits into two
    # groups, each of which may fall below the two occurrences it needs, and the series is then not
    # recognised at all.  It fails visibly — both halves are now listed, each saying it was seen once —
    # and merging the two counterparties reunites it, carrying any hand-set frequency with it.
    def groups = @rows.group_by { |row| row.counterparty_id || row.description }

    def payee_keys = (groups.keys + @schedules.keys).uniq

    # `[]` rather than `fetch`: a ruling can name a counterparty that has since been destroyed, and a
    # KeyError deep in the forecast is a poor way to learn it.  The id stands in as the name there, which
    # is ugly and is meant to be — it is a row the reader should withdraw.
    def label_for(key) = key.is_a?(Integer) ? counterparties[key]&.name || "##{key}" : key

    # One load for every counterparty named by the history or by a ruling, rather than one per payment.
    def counterparties
      ids = @rows.filter_map(&:counterparty_id) + @schedules.keys.grep(Integer)

      @counterparties ||= Account.where(id: ids.uniq).index_by(&:id)
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

    def candidate_for(key, rows)
      months = evidence(rows)
      inferred = inferred_cadence(months)
      schedule = @schedules[key]

      if schedule.nil?
        cadence = inferred
        status = inferred ? liveness(months, inferred) : inference_failure(months)
      elsif schedule.regular?
        # A cadence given by hand answers both questions inference could not — how often, and whether a
        # single sighting or a ragged one means anything — so neither of those rejections applies to it.
        # Staleness still does: it is a statement about *this* payee having stopped, which the reader
        # cannot have meant to deny by naming its frequency, and without it a cancelled direct debit
        # named by hand would be forecast for ever.
        cadence = schedule.cadence_months
        status = liveness(months, cadence)
      else
        cadence = nil
        status = :suppressed
      end

      payment_for(key, rows, months, cadence: cadence, status: status, inferred: inferred,
                                     set_by_hand: !schedule.nil?)
    end

    # What the history says the cadence is, or nil where it cannot say: too few occurrences to measure a
    # gap, or a gap longer than any cadence a payment is really on.
    def inferred_cadence(months)
      return nil if months.count < MINIMUM_OCCURRENCES

      raw = median_gap(months.map(&:first))
      return nil if raw > CADENCES.max

      CADENCES.min_by { |candidate| (candidate - raw).abs }
    end

    # Which of the three ways inference failed, so the screen can say which.  Nothing at all and seen
    # once are worth separating: a ruling rescues the second today and cannot rescue the first at all.
    def inference_failure(months)
      return :unseen if months.empty?

      months.count < MINIMUM_OCCURRENCES ? :seen_once : :erratic
    end

    # Finished, not merely quiet.  A cadence's worth of silence plus a month's grace.
    def liveness(months, cadence)
      # No occurrence in a completed month at all, so there is no amount to predict from, whatever the
      # reader has said about how often it comes.  A payee first seen in the month being forecast joins
      # the forecast next month; it has already gone out, so nothing is owed for it now either way.
      return :unseen if months.empty?

      @index - months.last.first > cadence + 1 ? :finished : :forecast
    end

    def payment_for(key, rows, months, cadence:, status:, inferred:, set_by_hand:)
      last_index, amount = months.last
      landed = rows.select { |row| row.month_index == @index }

      Forecast::Payment.new(
        key: key,
        label: label_for(key),
        counterparty: counterparty_for(key),
        # The amount is the **most recent** occurrence, not an average of them.  This looks lazy and is
        # not: the whole reason to predict a category this way rather than by its average is that a direct
        # debit steps up, and the new figure is what next month will cost.  Averaging the last few lags
        # precisely the change the method exists to catch.  The price is a genuinely variable bill, where
        # the answer is to forecast that category by its average instead — which the README says.
        amount: amount || latest_amount(rows),
        cadence: cadence,
        last_seen: last_index && rows.select { |row| row.month_index == last_index }.map(&:date).max,
        due: status == :forecast && ((@index - last_index) % cadence).zero?,
        landed_on: landed.map(&:date).min,
        landed_amount: landed.sum(Money.new(0), &:amount),
        status: status,
        inferred_cadence: inferred,
        set_by_hand: set_by_hand
      )
    end

    # The figure to show for a payee with nothing in a completed month yet.  It is not what the forecast
    # uses — see #evidence — but a row with no amount against it would say less than it could.
    #
    # Nil rather than zero where there is no history at all, which is a ruling that has outlived its
    # payee: £0.00 beside it would read as a payment that costs nothing rather than one that is not there.
    def latest_amount(rows)
      return nil if rows.empty?

      latest = rows.map(&:month_index).max

      rows.select { |row| row.month_index == latest }.sum(Money.new(0), &:amount)
    end

    def counterparty_for(key) = key.is_a?(Integer) ? counterparties[key] : nil

    def median_gap(indices)
      gaps = indices.each_cons(2).map { |before, after| after - before }
      sorted = gaps.sort
      middle = sorted.size / 2

      sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
    end
end
