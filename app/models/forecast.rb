# Predicting what a calendar month will cost, category by category.
#
# Nothing here is stored.  The whole forecast is derived from the transactions each time it is asked
# for; the only things on disk are the choice of method on each category and the figures the reader has
# typed in by hand.  A stored forecast that disagreed with the transactions beneath it would be worse
# than no forecast at all, and recomputing a few thousand rows costs milliseconds.
#
# Two conventions hold throughout, and both are load-bearing.
#
# **Everything counts in whole months, never in days.**  A month is its index — see #month_index below —
# and gaps between payments are differences between indices.  That is what makes February, leap years
# and thirty-day months a non-question rather than a set of edge cases: the only day arithmetic in the
# module is the one date range used to pick out a month's own transactions.
#
# **Spend is a positive magnitude here, though it is negative everywhere else in the application.**  The
# conversion happens in exactly one place, Forecast::History, and nothing else in the module touches
# amount_pence.  Three things drive it: the module's central rule is `[expected - actual, 0].max`, whose
# negative twin reads as a bug at every review forever; the reader types "600" for a holiday, not "-600",
# so a stored hand-entered figure has to be positive and cannot sit beside computed negatives; and the
# screen shows outgoings only, so the sign distinguishes nothing and only costs a column of minus signs.
module Forecast
  # The cadences a real payment actually uses, and what each is called on screen.
  #
  # One map rather than a list of numbers in the detector and a list of words in a view.  It is the
  # source of both: `Forecast::RegularPayments::CADENCES` is its keys, the select on the category screen
  # is its pairs, and `Forecast::Payment#cadence_label` is a lookup in it.  A raw median gap of two or
  # five months is noise around one of these rather than a schedule anything is on.
  CADENCE_LABELS = { 1 => "Monthly", 3 => "Quarterly", 6 => "Twice a year", 12 => "Yearly" }.freeze

  # A month as a single integer, so that "three months apart" is subtraction.
  #
  # @param [Date] date
  # @return [Integer]
  def self.month_index(date) = (date.year * 12) + date.month - 1

  # The first day of the month an index names.
  #
  # @param [Integer] index
  # @return [Date]
  def self.month_from_index(index) = Date.new(index / 12, (index % 12) + 1, 1)
end
