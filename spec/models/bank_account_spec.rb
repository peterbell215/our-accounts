require 'rails_helper'

describe BankAccount, type: :model do
  subject(:account) { Account.find_by_name("Lloyds Account") || FactoryBot.create(:lloyds_account) }

  describe 'FactoryBot' do
    specify { expect(account.name).to eq "Lloyds Account" }
  end

  describe 'validations' do
    specify { expect(FactoryBot.build(:lloyds_account, opening_balance: nil)).to_not be_valid }
    specify { expect(FactoryBot.build(:lloyds_account, sortcode: '00')).to_not be_valid }
    specify { expect(FactoryBot.build(:lloyds_account, account_number: '00')).to_not be_valid }
  end
end
