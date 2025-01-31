module Balances
  extend ActiveSupport::Concern

  class_methods do
    @balances = true
  end

  included do
    has_many :transactions

    validates :opening_balance, presence: true
  end
end