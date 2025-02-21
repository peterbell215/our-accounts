require 'rails_helper'

describe CreditCardAccount, type: :model do
  subject(:account) { FactoryBot.create(:barclay_card_account) }

  describe 'FactoryBot' do
    specify { expect(account.name).to eq "Barclaycard" }
  end

  describe 'validations' do
    specify { expect(FactoryBot.build(:lloyds_account, opening_balance: nil)).to_not be_valid }
    specify { expect(FactoryBot.build(:lloyds_account, account_number: '00')).to_not be_valid }
  end
end
