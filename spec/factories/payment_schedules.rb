FactoryBot.define do
  # A frequency the reader has set by hand.  No default payee: a schedule names either a counterparty or
  # a description, and which one it is depends entirely on what the caller is testing.
  factory :payment_schedule do
    category       { create(:subscriptions_category) }
    cadence_months { 1 }
  end
end
