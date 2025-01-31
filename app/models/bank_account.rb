# Class to represent a bank account
class BankAccount < Account
  include Balances

  validates :sortcode, presence: true, format: { with: /\A[0-9]{2}-[0-9]{2}-[0-9]{2}\z/, message: "sortcode format" }
  validates :account_number, presence: true, format: { with: /\A[0-9]{8}\z/, message: "sortcode format" }
end