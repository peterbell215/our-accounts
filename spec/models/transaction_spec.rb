require 'rails_helper'

RSpec.describe Transaction do
  before do
    create(:import_matcher_octopus_energy)
  end

  subject!(:trx) { build(:octopus_energy_imported_trx, amount: amount, balance: balance) }

  let!(:lloyds_account) { BankAccount.find_by_name("Lloyds Account") || create(:lloyds_account) }
  let(:amount) { Money.from_amount(-50.00) }
  let(:balance) { lloyds_account.opening_balance + amount }

  describe "#find_match" do
    before { trx.find_match }

    specify("counterparty") { expect(trx.counterparty_id).to eql Counterparty.find_by_name("Octopus Energy").id }
    specify("category") { expect(trx.category_id).to eql Category.find_by_name("Utilities").id }
  end

  # How the transaction list writes the counterparty: it offers the existing names through a datalist, so
  # what arrives is a name rather than an id.
  describe '#counterparty_name=' do
    let!(:octopus) { Counterparty.find_by_name("Octopus Energy") || create(:octopus_energy) }

    it 'links the counterparty of that name' do
      trx.counterparty_name = "Octopus Energy"

      expect(trx).to be_valid
      expect(trx.counterparty).to eq octopus
    end

    it 'does not care about case or surrounding space' do
      trx.counterparty_name = "  octopus energy  "

      expect(trx).to be_valid
      expect(trx.counterparty).to eq octopus
    end

    it 'clears the counterparty when left blank' do
      trx.counterparty = octopus
      trx.counterparty_name = ""

      expect(trx).to be_valid
      expect(trx.counterparty).to be_nil
    end

    # Silently creating one would add to the sprawl of raw statement names the analysis import already left.
    context 'with a name no counterparty has' do
      it 'is invalid and says so against the field that was typed into' do
        trx.counterparty_name = "Ocotpus Enrgy"

        expect(trx).not_to be_valid
        expect(trx.errors[:counterparty_name].first).to eq('"Ocotpus Enrgy" is not a counterparty')
      end

      it 'does not create one' do
        expect { trx.counterparty_name = "Ocotpus Enrgy" }.not_to change(Counterparty, :count)
      end
    end

    it 'will not match one of the household’s own accounts' do
      trx.counterparty_name = "Lloyds Account"

      expect(trx).not_to be_valid
    end
  end

  describe '#sequence' do
    context 'when no previous transaction in account' do
      it "sets the sequence to 0" do
        trx.sequence

        expect(trx.day_index).to eql 0
        expect(trx.balance).to eql balance
      end
    end

    context 'when previous transactions in account on same date' do
      let(:balance) { Money.from_amount(700.00) }

      it 'calculates the balance based on previous transaction balances' do
        create_list(:matched_transaction, 5)
        trx.sequence
        expect(trx.day_index).to eql 6
        expect(trx.balance).to eql balance
      end
    end

    context 'when imported balance does not agree with calculated balance' do
      let(:balance) { Money.from_amount(500.00) }

      it 'raises an ImportError exception' do
        expect { trx.sequence }.to raise_error ImportError
      end
    end

    context 'when imported balance is not set' do
      let(:balance) { nil }

      it 'calculates the balance based on the opening balance' do
        trx.sequence
        expect(trx.balance).to eql Money.from_amount(950.00)
      end

      it 'calculates the balance from the previous transaction balance on same day' do
        create_list(:matched_transaction, 5)
        trx.sequence
        expect(trx.balance).to eql Money.from_amount(700.00)
        expect(trx.day_index).to eql 6
      end

      it 'calculates the balance from the previous transaction balance on preceding day' do
        create_list(:matched_transaction, 5, date: Date.new(2024, 7, 13))
        trx.sequence
        expect(trx.balance).to eql Money.from_amount(700.00)
        expect(trx.day_index).to eql 0
      end
    end
  end
end
