class Transaction < ApplicationRecord
  belongs_to :creditor
  belongs_to :debitor

  validates :date, presence: true
  validates :amount, presence: true
  validates :creditor, presence: true
  validates :debitor, presence: true
end
