FactoryBot.define do
  factory :imported_transaction do
    factory :amazon_imported_trx do
      import_account { BankAccount.find_by_name("Lloyds Account") || FactoryBot.create(:lloyds_account) }

      date        { Date.new(2024, 7, 16) }
      trx_type    { 'DEB' }
      description { "AMAZON* 204-813115" }
      amount      { Money.from_amount(63.50) }
      balance     { Money.from_amount(334.60) }
    end

    factory :octopus_energy_imported_trx do
      import_account { BankAccount.find_by_name("Lloyds Account") || FactoryBot.create(:lloyds_account) }

      date        { Date.new(2024, 11, 19) }
      trx_type    { 'DD' }
      description { "OCTOPUS ENERGY" }
      amount      { Money.from_amount(218.85) }
      balance     { Money.from_amount(1383.14) }
    end
  end
end