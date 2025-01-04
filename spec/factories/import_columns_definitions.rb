# spec/factories/import_column_definitions.rb
FactoryBot.define do
  factory :import_columns_definition do
    factory :lloyds_import_columns_definition do
      account factory: :lloyds_account

      date_column { 0 }
      date_format             { "%d/%m/%Y" }
      transaction_type_column { 1 }
      sortcode_column         { 2 }
      account_number_column   { 3 }
      other_party_column      { 4 }
      amount_column           { nil }
      debit_column            { 5 }
      credit_column           { 6 }
      balance_column          { 7 }
    end
  end
end
