# Class to represent a credit card account
class CreditCardAccount < Account
  validates :opening_balance, presence: true
end
