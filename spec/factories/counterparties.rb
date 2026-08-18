FactoryBot.define do
  factory :counterparty do
    factory :octopus_energy do
      name            { "Octopus Energy" }
      account_number  { '01234567' }
    end

    factory :amazon do
      name            { "Amazon" }
    end
  end
end
