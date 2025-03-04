FactoryBot.define do
  factory :transaction do
    factory :imported_transaction do
      factory :salary_transaction do
        account     { BankAccount.find_by_name("Lloyds Account") || FactoryBot.create(:lloyds_account) }

        date        { Date.new(2024, 7, 30) }
        trx_type    { "BGC" }
        description { "EMPLOYER CURRENT" }
        amount      { Money.from_amount(1200.00) }
        balance     { Money.from_amount(2000.00) }
      end

      factory :amazon_imported_trx do
        account     { BankAccount.find_by_name("Lloyds Account") || FactoryBot.create(:lloyds_account) }

        date        { Date.new(2024, 7, 16) }
        trx_type    { 'DEB' }
        description { "AMAZON* 204-813115" }
        amount      { Money.from_amount(-63.50) }
        balance     { Money.from_amount(334.60) }
      end

      factory :octopus_energy_imported_trx do
        account     { BankAccount.find_by_name("Lloyds Account") || FactoryBot.create(:lloyds_account) }

        date        { Date.new(2024, 11, 19) }
        trx_type    { 'DD' }
        description { "OCTOPUS ENERGY" }
        amount      { Money.from_amount(-218.85) }
        balance     { Money.from_amount(1383.14) }
      end

      factory :bertaux_transaction_for_export do
        account     { BankAccount.find_by_name("Lloyds Account") || FactoryBot.create(:lloyds_account) }
        date        { Date.new(2024, 12, 12) }
        trx_type    { "DEB" }
        description { 'Maison Bertaux' }
        amount      { Money.from_amount(-5.95) }
        balance     { Money.from_amount(1525.80) }
      end

      factory :tesco_shop do
        account     { BankAccount.find_by_name("Lloyds Account") || FactoryBot.create(:lloyds_account) }
        trx_type    { "DEB" }
        description { 'TESCO STORES 2889' }
        amount      { Money.from_amount(-5.95) }
      end
  end

    factory :matched_transaction do
      account     { BankAccount.find_by_name("Lloyds Account") || FactoryBot.create(:lloyds_account) }
      date        { Date.new(2024, 11, 19) }
      category_id { Category.find_by_name("Utilities").id }
      other_party { TradingAccount.find_by_name("Octopus Energy") || FactoryBot.create(:octopus_energy_account) }
      amount      { Money.from_amount(-50.00) }

      sequence :day_index

      balance do
        previous_transaction = Transaction.where(account_id: account.id).order(:date, :day_index).last
        (previous_transaction&.balance || account.opening_balance) + amount
      end
    end
  end
end
