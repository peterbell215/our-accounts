require 'rails_helper'

describe Account, type: :model do
  describe 'bank account' do
    subject(:lloyds_account) { FactoryBot.create(:lloyds_account) }

    let(:first_lloyds_transaction) { FactoryBot.build(:first_lloyds_transaction) }
    let(:second_lloyds_transaction) { FactoryBot.build(:second_lloyds_transaction) }

    context
  end

end