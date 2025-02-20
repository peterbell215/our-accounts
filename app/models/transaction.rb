# A transaction represents
class Transaction < ApplicationRecord
  belongs_to :account, optional: false

  belongs_to :category
  belongs_to :other_party, class_name: "Account", foreign_key: "other_party_id"

  validates :date, presence: true
  validates :amount, presence: true

  monetize :amount_pence, :balance_pence
end