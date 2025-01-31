require 'rails_helper'

describe TradingAccount, type: :model do
  subject(:account) { FactoryBot.create(:octopus_energy_account) }

  describe 'FactoryBot' do
    specify { expect(account.name).to eq "Octopus Energy" }
  end

  describe '#balances?' do
    specify { expect(account.class.balances?).to be_falsey }
  end

  describe 'validations' do
    specify { expect(FactoryBot.build(:octopus_energy_account, opening_balance: nil)).to be_valid }
  end
end