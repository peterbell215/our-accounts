FactoryBot.define do
  factory :import_matcher do
    account { BankAccount.find_by_name("Lloyds Account") || FactoryBot.create(:lloyds_account) }

    factory :import_matcher_octopus_energy do
      category             { Category.find_by(name: 'Utilities') }
      counterparty          { Counterparty.find_by(name: "Octopus Energy") || FactoryBot.create(:octopus_energy) }

      trx_type             { 'DD' }
      description          { 'OCTOPUS ENERGY' }
      description_is_regex { false }
    end

    # A rule that categorises without naming a counterparty, which is all AnalysisImporter can derive when
    # the description is too short to be an Account name.
    factory :import_matcher_without_counterparty do
      category             { Category.find_by(name: 'Utilities') }
      counterparty          { nil }

      trx_type             { nil }
      description          { 'O2' }
      description_is_regex { false }
    end

    factory :import_matcher_amazon do
      category             { Category.find_by(name: 'Shopping') }
      counterparty          { Counterparty.find_by(name: "Amazon") || FactoryBot.create(:amazon) }

      trx_type             { 'DEB' }
      description          { 'AMAZON' }
      description_is_regex { true }
    end

    # An amount-conditioned rule: the usual APPLE.COM/BILL charge is a fixed subscription, so this catches
    # exactly that amount and leaves any other amount against the same description to a default rule
    # written alongside it (see import_matcher_apple_purchases_default).
    factory :import_matcher_apple_subscription do
      category             { Category.find_by(name: 'Shopping') }
      counterparty          { nil }

      trx_type             { nil }
      description          { 'APPLE.COM/BILL' }
      description_is_regex { false }
      amount_comparison    { 'equal_to' }
      amount               { Money.from_amount(-7.99) }
    end

    # The default for the same description: no amount condition, so it only ever gets to run on the amounts
    # import_matcher_apple_subscription does not claim, per in_match_order.
    factory :import_matcher_apple_purchases_default do
      category             { Category.find_by(name: 'Travel') }
      counterparty          { nil }

      trx_type             { nil }
      description          { 'APPLE.COM/BILL' }
      description_is_regex { false }
    end
  end
end
