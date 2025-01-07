FactoryBot.define do
  factory :account do
    factory :lloyds_account do
      name            { "Lloyds Account" }
      account_number  { '01234567'}
      sortcode        { '30-00-00' }
      opening_date    { Date.new(2023, 1, 3) }
      opening_balance { Money.from_amount(120.0) }
    end

    factory :barclay_card_account do
      name            { "Barclaycard" }
      account_number  { '1234-1234-1234-1234'}
      sortcode        { nil }
      opening_date    { Date.new(2024, 1, 3) }
      opening_balance { Money.from_amount(-500.0) }
    end
  end
end