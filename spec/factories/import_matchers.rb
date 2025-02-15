FactoryBot.define do
  factory :import_matcher do
    account { BankAccount.find_by_name("Lloyds Account") || FactoryBot.create(:lloyds_account) }

    factory :import_matcher_octopus_energy do
      category             { Category.find_by(name: 'Utilities') }
      other_party          { TradingAccount.find_by(name: "Octopus Energy") || FactoryBot.create(:octopus_energy_account) }

      trx_type             { 'DD' }
      description          { 'OCTOPUS ENERGY'}
      description_is_regex { false }
    end

    factory :import_matcher_amazon do
      category             { Category.find_by(name: 'Shopping') }
      other_party          { TradingAccount.find_by(name: "Amazon") || FactoryBot.create(:amazon_account) }

      trx_type             { 'DEB' }
      description          { 'AMAZON' }
      description_is_regex { true }
    end
  end
end
