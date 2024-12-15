class Account < ApplicationRecord
  has_many :transactions

  monetize :opening_balance_pence

  validates :name, presence: true, uniqueness: true, length: { minimum: 3, maximum: 50 }
  validates :opening_balance, presence: true
end
