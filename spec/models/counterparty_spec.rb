require 'rails_helper'

describe Counterparty, type: :model do
  subject(:counterparty) { FactoryBot.create(:octopus_energy) }

  describe 'FactoryBot' do
    specify { expect(counterparty.name).to eq "Octopus Energy" }
  end

  describe 'validations' do
    specify { expect(FactoryBot.build(:octopus_energy, opening_balance: nil)).to be_valid }
  end

  # A counterparty's transactions belong to the household's accounts, not to it, so #transactions does not
  # reach them.  Linking every dealing with one vendor is the reason it is modelled as an account at all.
  describe '#counterparty_transactions' do
    let(:lloyds) { create(:lloyds_account) }
    let(:barclaycard) { create(:barclay_card_account) }

    it 'gathers that vendor’s transactions from every account' do
      from_lloyds = create(:tesco_shop, account: lloyds, counterparty: counterparty, date: Date.new(2024, 7, 1))
      from_card = create(:tesco_shop, account: barclaycard, counterparty: counterparty, date: Date.new(2024, 7, 2))
      create(:tesco_shop, account: lloyds, date: Date.new(2024, 7, 3))

      expect(counterparty.counterparty_transactions).to contain_exactly(from_lloyds, from_card)
    end

    it 'is empty on #transactions, which is the account-owns-it side' do
      create(:tesco_shop, account: lloyds, counterparty: counterparty, date: Date.new(2024, 7, 1))

      expect(counterparty.transactions).to be_empty
    end
  end

  describe '#destroy' do
    let(:lloyds) { create(:lloyds_account) }

    it 'releases its transactions rather than deleting them or tripping over the foreign key' do
      transaction = create(:tesco_shop, account: lloyds, counterparty: counterparty, date: Date.new(2024, 7, 1))

      expect { counterparty.destroy! }.not_to change(Transaction, :count)
      expect(transaction.reload.counterparty).to be_nil
    end

    it 'leaves a rule that pointed at it still assigning its category' do
      matcher = create(:import_matcher_octopus_energy, counterparty: counterparty)

      counterparty.destroy!

      expect(matcher.reload.counterparty).to be_nil
      expect(matcher.category.name).to eq("Utilities")
    end
  end
end
