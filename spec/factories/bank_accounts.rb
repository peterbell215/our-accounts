FactoryBot.define do
  factory :bank_account do
    factory :lloyds_account do
      name            { "Lloyds Account" }
      account_number  { '01234567'}
      sortcode        { '30-00-00' }
      opening_date    { Date.new(2023, 1, 3) }
      opening_balance { Money.from_amount(120.0) }
    end
  end
end