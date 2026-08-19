# A figure the reader has entered by hand for one category in one month.
#
# Most categories are predicted from their own history, but some — Holidays is the standing example —
# are too lumpy for any history to say anything useful about.  For those the reader supplies the number,
# and this is the only thing the forecasting module stores beyond the choice of method itself.
#
# Deliberately *not* validated against the category's forecast method.  Someone may enter a figure and
# then change the method, or change their mind back, and an unused figure is harmless — it is quietly
# picked up again if they switch back.  The category's page says so rather than treating it as an error.
class ManualForecast < ApplicationRecord
  belongs_to :category

  monetize :amount_pence

  # A month is identified by its first day throughout the forecast.  Normalising here is what makes the
  # unique index mean what it says: without it, 1-Mar and 17-Mar would be two predictions for March.
  before_validation { self.month = month.beginning_of_month if month }

  validates :month, presence: true
  validates :category_id, uniqueness: { scope: :month }
  # Zero is meaningful — "nothing on Holidays in March".  Negative is not: the forecast deals in spend as
  # a positive magnitude, and a negative prediction would be income by another name.
  validates :amount_pence, numericality: { greater_than_or_equal_to: 0 }
end
