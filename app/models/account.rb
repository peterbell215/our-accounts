# Account superclass.  Sub-classed for specific types of accounts.
class Account < ApplicationRecord
  has_many :transactions, dependent: :destroy
  has_many :import_columns_definitions, dependent: :destroy
  has_many :import_matchers, dependent: :destroy

  # The other side of Transaction#other_party and ImportMatcher#other_party.  For a TradingAccount these
  # are the vendor's dealings with us — the whole point of modelling a counterparty as an account — and
  # they belong to other accounts, so #transactions above does not reach them.
  #
  # :nullify rather than :destroy: deleting a counterparty must not delete the household's transactions,
  # and a rule with no counterparty still assigns its category.  It also keeps #destroy from tripping over
  # the foreign key on transactions.other_party_id.
  has_many :counterparty_transactions, class_name: "Transaction", foreign_key: :other_party_id,
           inverse_of: :other_party, dependent: :nullify
  has_many :counterparty_matchers, class_name: "ImportMatcher", foreign_key: :other_party_id,
           inverse_of: :other_party, dependent: :nullify

  validates :name, presence: true, uniqueness: true, length: { minimum: 3, maximum: 50 }

  monetize :opening_balance_pence, allow_nil: true
end
