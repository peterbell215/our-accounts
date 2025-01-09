require 'rails_helper'

RSpec.describe ImportMatcher, type: :model do
  describe '#match' do
    context 'when description is not regex' do
      subject(:import_matcher) { create(:import_matcher_octopus_energy) }

      context('when it matches') do
        let(:octopus_energy) { build(:octopus_energy, import_account: lloyds_account) }
        let(:lloyds_account) { Account.find_by_name('Lloyds Account') }

        specify { expect(import_matcher.match(octopus_energy)).to be true }
      end

      context 'when account_id does not match' do
        let(:octopus_energy) { build(:octopus_energy, import_account: barclay_card_account) }
        let(:barclay_card_account) { create(:barclay_card_account) }

        specify { expect(import_matcher.match(octopus_energy)).to be false }
      end
    end
  end
end