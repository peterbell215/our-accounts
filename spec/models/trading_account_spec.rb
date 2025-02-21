require 'rails_helper'

describe TradingAccount, type: :model do
  subject(:account) { FactoryBot.create(:octopus_energy_account) }

  describe 'FactoryBot' do
    specify { expect(account.name).to eq "Octopus Energy" }
  end

  describe 'validations' do
    specify { expect(FactoryBot.build(:octopus_energy_account, opening_balance: nil)).to be_valid }
  end
end
