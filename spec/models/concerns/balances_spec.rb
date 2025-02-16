require 'rails_helper'

RSpec.describe Balances do
  before do
    create(:import_matcher_octopus_energy)
  end

  let!(:lloyds_account) { BankAccount.find_by_name("Lloyds Account") || create(:lloyds_account) }

  let(:imported_trx) { build(:octopus_energy_imported_trx, amount: amount, balance: balance) }
  let(:amount) { Money.from_amount(-50.00) }
  let(:balance) { lloyds_account.opening_balance + amount }

  describe "it correctly imports the trx's" do
    subject!(:trx) { lloyds_account.add_transaction(imported_trx) }

    specify("date") { expect(trx.date).to eql imported_trx.date }
    specify("account") { expect(trx.account_id).to eql lloyds_account.id }
    specify("amount") { expect(trx.amount).to eql amount }
    specify("other_party") { expect(trx.other_party_id).to eql TradingAccount.find_by_name("Octopus Energy").id }
    specify("category") { expect(trx.category_id).to eql Category.find_by_name("Utilities").id }
  end

  context 'when no previous transaction in account' do
    subject!(:trx) { lloyds_account.add_transaction(imported_trx) }

    specify("day_index") { expect(trx.day_index).to eql 0 }
  end

  context 'when previous transactions in account on same date' do
    let(:balance) { Money.from_amount(700.00) }

    it 'calculates the balance based on previous transaction balances' do
      create_list(:transaction, 5)
      trx = lloyds_account.add_transaction(imported_trx)

      expect(trx.day_index).to eql 6
    end
  end

  context 'when imported balance does not agree with calculated balance' do
    let(:balance) { Money.from_amount(500.00) }

    it 'raises an ImportError exception' do
      expect { lloyds_account.add_transaction(imported_trx) }.to raise_error ImportError
    end
  end

  context 'when imported balance is not set' do
    let(:balance) { nil }

    it 'calculates the balance based on the opening balance' do
      trx = lloyds_account.add_transaction(imported_trx)
      expect(trx.balance).to eql Money.from_amount(950.00)
    end

    it 'calculates the balance from the previous transaction balance on same day' do
      create_list(:transaction, 5)
      trx = lloyds_account.add_transaction(imported_trx)
      expect(trx.balance).to eql Money.from_amount(700.00)
      expect(trx.day_index).to eql 6
    end

    it 'calculates the balance from the previous transaction balance on preceding day' do
      create_list(:transaction, 5, date: Date.new(2024, 7, 13))
      trx = lloyds_account.add_transaction(imported_trx)
      expect(trx.balance).to eql Money.from_amount(700.00)
      expect(trx.day_index).to eql 0
    end
  end
end
