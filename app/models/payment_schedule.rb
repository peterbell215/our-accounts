# A frequency the user has set by hand for one payee in one category.
#
# Forecast::RegularPayments infers a cadence from the history, and its three rejections are all
# conservative and all sometimes wrong: a brand-new direct debit is invisible until its second
# occurrence, an annual premium paid a fortnight either side of its anniversary reads as erratic, and a
# payee can be latched onto by coincidence.  This is how the user overrules it.
#
# **A row exists only where the user has ruled on a payee.**  No row means "work it out from the
# history", which is why nothing creates these in bulk and why the forecast is unchanged for anybody who
# never opens the screen.
#
# **`cadence_months` is null on a row that exists, meaning "not a regular payment".**  Three states have
# to fit — work it out, this cadence, not a regular payment — and the absence of a row is already the
# first, so one column carries the other two.  The alternatives cost more than the double duty does:
# zero as a sentinel puts a nonsense value into the `silence % cadence` arithmetic in the detector,
# where it raises ZeroDivisionError one missing guard away; and a separate boolean spends two columns
# and a cross-column validation on three states.
class PaymentSchedule < ApplicationRecord
  # What the form sends for the two choices that are not a number of months.  A blank clears the ruling
  # — the same gesture, and the same meaning, as emptying the hand-entered figure on the forecast.
  WORK_IT_OUT = "".freeze
  NOT_REGULAR = "none".freeze

  belongs_to :category
  # class_name: "Account" because Counterparty is STI on accounts, matching ImportMatcher#counterparty.
  belongs_to :counterparty, class_name: "Account", optional: true

  # Blank becomes nil, in the same spirit as ImportMatcher#trx_type and for the same kind of reason: an
  # empty description is not a payee, but the partial unique index treats it as present while the
  # validation below treats it as absent, so a `""` would be a row that neither guard can see.
  normalizes :description, with: ->(text) { text.presence }

  # A payee is its counterparty where it has one and its exact description where it does not, which is
  # how Forecast::RegularPayments groups them — plenty of direct debits never acquired a counterparty.
  # Both at once would be two names for one payee and neither would be a ruling on anything.
  validate :counterparty_or_description

  # Load-bearing rather than cosmetic.  The detector does `silence % cadence`, so a cadence of zero
  # raises and a cadence of seven quietly invents a schedule nothing is on.  The select only offers
  # these four, so anything else arrived from a hand-crafted request.
  validates :cadence_months, inclusion: { in: Forecast::CADENCE_LABELS.keys }, allow_nil: true

  # How Forecast::RegularPayments identifies the same payee, so that the two agree in one place rather
  # than by coincidence.
  #
  # @return [Integer, String]
  def payee_key = counterparty_id || description

  # Whether this ruling says the payee is a regular payment at all.
  def regular? = !cadence_months.nil?

  # Applies a screen's worth of rulings, one row per payee.
  #
  # All or nothing: a cadence that fails validation can only have come from a forged form, and rolling
  # the set back is both easier to report and easier to reason about than a half-applied screen.
  #
  # @param [Category] category
  # @param [Enumerable<ActionController::Parameters, Hash>] rows each with counterparty_id, description
  #   and cadence_months
  # @raise [ActiveRecord::RecordInvalid]
  def self.apply(category:, rows:)
    transaction { rows.each { |row| rule(category, row) } }
  end

  # @return [void]
  def self.rule(category, row)
    counterparty_id = row[:counterparty_id].presence
    # The description only identifies a payee that has no counterparty, so it is ignored when one is
    # named.  Otherwise a forged form could store both and satisfy neither index.
    description = counterparty_id ? nil : row[:description].presence
    return if counterparty_id.nil? && description.nil?

    schedule = find_or_initialize_by(category: category, counterparty_id: counterparty_id,
                                     description: description)

    case row[:cadence_months].to_s
    when WORK_IT_OUT then schedule.destroy if schedule.persisted?
    when NOT_REGULAR then schedule.update!(cadence_months: nil)
    else                  schedule.update!(cadence_months: row[:cadence_months].to_i)
    end
  end
  private_class_method :rule

  private
    def counterparty_or_description
      return if counterparty_id.present? ^ description.present?

      errors.add(:base, "A payment schedule names either a counterparty or a description, not both and not neither.")
    end
end
