FactoryBot.define do
  factory :transaction do
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
