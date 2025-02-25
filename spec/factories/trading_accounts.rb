FactoryBot.define do
  factory :trading_account do
    factory :octopus_energy_account do
      name            { "Octopus Energy" }
      account_number  { '01234567' }
    end

    factory :amazon_account do
      name            { "Amazon" }
    end
  end
end
