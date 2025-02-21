FactoryBot.define do
  factory :credit_card_account do
    factory :barclay_card_account do
      name            { "Barclaycard" }
      account_number  { '1234-1234-1234-1234' }
      sortcode        { nil }
      opening_date    { Date.new(2024, 1, 3) }
      opening_balance { Money.from_amount(-500.0) }
    end
  end
end
