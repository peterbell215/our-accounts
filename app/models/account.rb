# Account superclass.  Sub-classed for specific types of accounts.
class Account < ApplicationRecord
  has_many :transactions, dependent: :destroy
  has_many :import_columns_definitions, dependent: :destroy

  validates :name, presence: true, uniqueness: true, length: { minimum: 3, maximum: 50 }

  monetize :opening_balance_pence, allow_nil: true
end
