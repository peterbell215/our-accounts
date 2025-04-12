# Class to represent a credit card account
class CreditCardAccount < Account
  validates :opening_balance, presence: true
  validates :account_number, format: {
    with: /\A\d{4}([- ]?)\d{4}\1\d{4}\1\d{4}\z/,
    message: "must be a valid credit card number format (e.g. 1234-5678-9012-3456 or 1234 5678 9012 3456)"
  }
end
