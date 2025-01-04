require 'rails_helper'

describe Account, type: :model do
  let(:account) { FactoryBot.create(:lloyds_account) }

  describe 'FactoryBot' do
    specify { expect(account.name).to eq "Lloyds Account" }
  end
end
