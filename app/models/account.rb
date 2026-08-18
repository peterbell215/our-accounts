# Account superclass.  Sub-classed for specific types of accounts.
class Account < ApplicationRecord
  has_many :transactions, dependent: :destroy
  has_many :import_columns_definitions, dependent: :destroy
  has_many :import_matchers, dependent: :destroy

  # The other side of Transaction#counterparty and ImportMatcher#counterparty.  For a Counterparty these
  # are the vendor's dealings with us — the whole point of modelling a counterparty as an account — and
  # they belong to other accounts, so #transactions above does not reach them.
  #
  # :nullify rather than :destroy: deleting a counterparty must not delete the household's transactions,
  # and a rule with no counterparty still assigns its category.  It also keeps #destroy from tripping over
  # the foreign key on transactions.counterparty_id.
  has_many :counterparty_transactions, class_name: "Transaction", foreign_key: :counterparty_id,
           inverse_of: :counterparty, dependent: :nullify
  has_many :counterparty_matchers, class_name: "ImportMatcher", foreign_key: :counterparty_id,
           inverse_of: :counterparty, dependent: :nullify

  # A name is typed on one screen and matched against typed text on another (Transaction#counterparty_name=),
  # so stray or doubled spaces are only ever a nuisance: " Tesco " renders in a transaction row and then
  # fails to match itself, leaving a row that cannot be saved.  Squish on write, which also normalises the
  # value in finders.
  normalizes :name, with: ->(name) { name&.squish }

  # Case-insensitively unique, because that is how names are looked up.  Were "TESCO" and "Tesco" both
  # allowed, a typed name would resolve to whichever one the database happened to return first.
  validates :name, presence: true, uniqueness: { case_sensitive: false },
            length: { minimum: 3, maximum: 50 }

  monetize :opening_balance_pence, allow_nil: true
end
