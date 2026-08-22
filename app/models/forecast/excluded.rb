# A category deliberately left out of the forecast.
#
# Paying off a credit card, or moving money between two of the household's own accounts, is not spending
# — the spending already happened on the card. Counting it would count the same money twice.
#
# A class rather than a branch in Forecast::Month for two reasons: it keeps every other object free of
# "unless excluded", and an excluded category still has to **appear** on the screen. A reader needs to
# see that card payments were left out, not merely find them missing.
class Forecast::Excluded
  # Nil rather than zero throughout: there is no prediction here, which is a different thing from a
  # prediction of nothing. The view renders empty cells and the totals skip the line entirely.
  def expected = nil

  def remaining(_spent) = nil
end
