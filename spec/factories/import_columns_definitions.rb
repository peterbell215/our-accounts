# spec/factories/import_column_definitions.rb
FactoryBot.define do
  factory :import_columns_definition do
    factory :lloyds_import_columns_definition do
      account                 { Account.find_by_name("Lloyds Account") || FactoryBot.create(:lloyds_account) }

      header                  { true }
      date_column             { "Transaction Date" }
      date_format             { "%d/%m/%Y" }
      trx_type_column         { "Transaction Type" }
      sortcode_column         { "Sort Code" }
      account_number_column   { "Account Number" }
      other_party_column      { "Transaction Description" }
      amount_column           { nil }
      debit_column            { "Debit Amount" }
      credit_column           { "Credit Amount" }
      balance_column          { "Balance" }
      reversed                { true }
    end

    factory :barclaycard_import_columns_definition do
      account                 { Account.find_by_name("Barclaycard") || FactoryBot.create(:barclay_card_account) }

      header                  { false }
      date_column             { 0 }
      date_format             { "%d %b %y" }
      other_party_column      { 1 }
      trx_type_column         { 4 }
      sortcode_column         { nil }
      account_number_column   { nil }
      amount_column           { nil }
      debit_column            { 5 }
      credit_column           { 6 }
      balance_column          { nil }
      credit_sign             { -1 }
      reversed                { false }
    end
  end
end