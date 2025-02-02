FactoryBot.define do
  factory :bank_account do
    transient do
      with_import_columns_definition { nil }
    end

    factory :lloyds_account do
      name            { "Lloyds Account" }
      account_number  { '01234567'}
      sortcode        { '30-00-00' }
      opening_date    { Date.new(2023, 1, 3) }
      opening_balance { Money.from_amount(120.0) }
    end

    after(:create) do |account, context|
      if context.with_import_columns_definition
        create(context.with_import_columns_definition, account: account)
      end
    end
  end
end