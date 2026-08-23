# One repeating payment the forecast has considered — a direct debit, a subscription, an annual premium.
#
# Built by Forecast::RegularPayments, one per payee in the category, whether or not it made it into the
# forecast: `status` says which, and it is rendered a row at a time both on the forecast's workings page
# and on the category screen, where the reader can see whether the guess is a good one and overrule it.
Forecast::Payment = Struct.new(
  :key, :label, :counterparty, :amount, :cadence, :last_seen, :due, :landed_on, :landed_amount,
  :status, :inferred_cadence, :set_by_hand,
  keyword_init: true
) do
  # Why this payee is, or is not, part of the forecast — and, where it is not, in the order a reader
  # would want to read them: the ones they have ruled on, then the ones a ruling would rescue, then the
  # ones nothing can.
  #
  # :forecast   — recognised and live, so it counts
  # :suppressed — the reader has said it is not a regular payment
  # :seen_once  — one occurrence in a completed month, so no cadence can be measured and none was given
  # :erratic    — it repeats, but the median gap is longer than any cadence a payment is really on
  # :finished   — a cadence that has gone quiet for longer than that cadence allows
  # :unseen     — nothing in a completed month at all, so there is no amount it could be forecast at
  STATUSES = %i[ forecast suppressed seen_once erratic finished unseen ].freeze

  # Is this payment part of the forecast at all?
  def forecast? = status == :forecast

  # Where this payee sorts among the others.  Deliberately leaves the two secondary keys alone, so the
  # forecast ones come out in exactly the order they always have — see Forecast::RegularPayments#payments.
  def status_order = STATUSES.index(status)

  # How this payee is identified — a counterparty, or a description where it has none.  Kept as the raw
  # key it was grouped under rather than derived from the label, because the label is prose and a ruling
  # has to be posted back against something exact.
  def counterparty_id = key.is_a?(Integer) ? key : nil
  def payee_description = key.is_a?(Integer) ? nil : key

  # Is this payment expected in the month being forecast?
  def due? = due

  # Has it already gone out?
  def landed? = !landed_on.nil?

  # Was its frequency set by hand rather than inferred?
  def set_by_hand? = set_by_hand

  # Does a hand-set frequency disagree with what the history would have said?  Worth showing: the reader
  # is entitled to see the guess they overruled, and to notice when the two have converged.
  def overrules_history? = set_by_hand? && !inferred_cadence.nil? && inferred_cadence != cadence

  # What this payment still adds to the month.
  #
  # It drops to nothing the moment the payment lands, and it drops to nothing *whatever the payment came
  # in at*.  That is the difference between predicting a category from its payments and predicting it
  # from its total: if the energy bill was expected at £218 and arrived at £248, this payment is settled
  # and the water bill still due is untouched.  Subtracting at the level of the category would quietly
  # eat £30 of the water bill instead.
  #
  # @return [Money]
  def remaining = forecast? && due? && !landed? ? amount : Money.new(0)

  # How the cadence reads on screen, or nil where there is none to read.
  #
  # @return [String, nil]
  def cadence_label = cadence && Forecast::CADENCE_LABELS.fetch(cadence, "Every #{cadence} months")

  # What the reader's ruling for this payee is, in the terms the form sends and stores: a number of
  # months, PaymentSchedule::NOT_REGULAR, or a blank meaning they have not ruled at all.
  #
  # @return [String]
  def schedule_value
    return PaymentSchedule::NOT_REGULAR if status == :suppressed
    return cadence.to_s if set_by_hand?

    PaymentSchedule::WORK_IT_OUT
  end
end
