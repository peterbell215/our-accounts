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

  # :destroy rather than :nullify, unlike the two above.  A PaymentSchedule names its payee either by
  # counterparty or by description, never neither, so a nullified counterparty_id would leave a row that
  # identifies nothing.  There is nothing to preserve either: the transactions this counterparty is
  # released from regroup under their own descriptions, so the ruling no longer applies to anything.
  has_many :counterparty_payment_schedules, class_name: "PaymentSchedule", foreign_key: :counterparty_id,
           inverse_of: :counterparty, dependent: :destroy

  # A name is typed on one screen and matched against typed text on another (Transaction#counterparty_name=),
  # so stray or doubled spaces are only ever a nuisance: " Tesco " renders in a transaction row and then
  # fails to match itself, leaving a row that cannot be saved.  Squish on write, which also normalises the
  # value in finders.
  normalizes :name, with: ->(name) { name&.squish }

  # Case-insensitively unique, because that is how names are looked up.  Were "TESCO" and "Tesco" both
  # allowed, a typed name would resolve to whichever one the database happened to return first.
  validates :name, presence: true, uniqueness: { case_sensitive: false },
            length: { minimum: 3, maximum: 50 }

  # How a name typed or read from a statement is looked up: case is insignificant, and so is stray space,
  # since #name is squished on write.  Ordered so that a legacy pair differing only in case — which the
  # validation above now prevents, but older data may still hold — resolves to the same one every time.
  scope :named, ->(name) { where("LOWER(name) = ?", name.to_s.squish.downcase).order(:id) }

  # The household's own accounts, as against the counterparties sharing this table.  Named because the
  # distinction is made in several places and "type IN (...)" spelled out at each of them says what it
  # does rather than what it means.
  scope :own, -> { where(type: %w[ BankAccount CreditCardAccount ]) }

  monetize :opening_balance_pence, allow_nil: true
end
