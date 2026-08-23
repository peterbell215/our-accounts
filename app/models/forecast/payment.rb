# One repeating payment the forecast believes it has recognised — a direct debit, a subscription, an
# annual premium.  Built by Forecast::RegularPayments; rendered a row at a time on the workings page,
# which is where the reader can see whether the guess is a good one.
Forecast::Payment = Struct.new(
  :label, :counterparty, :amount, :cadence, :last_seen, :due, :landed,
  keyword_init: true
) do
  # Is this payment expected in the month being forecast?
  def due? = due

  # Has it already gone out?
  #
  # `landed` is every occurrence inside the month being forecast, earliest first, rather than one date
  # and one amount.  A monthly payment billed on the 1st and again on the 29th falls twice inside the
  # same calendar month, and totalling the two against the earlier of the dates drew it as a single
  # charge for twice the money — on the page indistinguishable from a bill that had doubled.
  def landed? = landed.any?

  # What this payment still adds to the month.
  #
  # It drops to nothing the moment the payment lands, and it drops to nothing *whatever the payment came
  # in at*.  That is the difference between predicting a category from its payments and predicting it
  # from its total: if the energy bill was expected at £218 and arrived at £248, this payment is settled
  # and the water bill still due is untouched.  Subtracting at the level of the category would quietly
  # eat £30 of the water bill instead.
  #
  # @return [Money]
  def remaining = landed? || !due? ? Money.new(0) : amount

  # How the cadence reads on screen.
  #
  # @return [String]
  def cadence_label
    { 1 => "Monthly", 3 => "Quarterly", 6 => "Twice a year", 12 => "Yearly" }.fetch(cadence, "Every #{cadence} months")
  end
end
