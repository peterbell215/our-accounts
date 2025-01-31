# Account superclass.  Sub-classed for specific types of accounts.
class Account < ApplicationRecord
  validates :name, presence: true, uniqueness: true, length: { minimum: 3, maximum: 50 }

  monetize :opening_balance_pence, allow_nil: true

  def self.balances?
    @balances.nil? ? superclass.balances? : @balances
  end

  @balances = true
end