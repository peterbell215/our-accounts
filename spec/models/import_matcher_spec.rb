require 'rails_helper'

RSpec.describe ImportMatcher, type: :model do
  describe '#match' do
    context 'when account_id does not match' do
      subject(:import_matcher) { create(:import_matcher_octopus_energy) }

      let(:octopus_energy_imported_trx) { build(:octopus_energy_imported_trx, import_account: barclay_card_account) }
      let(:barclay_card_account) { create(:barclay_card_account) }

      specify { expect(import_matcher.match(octopus_energy_imported_trx)).to be false }
    end

    context 'when description is not regex' do
      subject(:import_matcher) { create(:import_matcher_octopus_energy) }

      context('when it matches') do
        let(:octopus_energy_imported_trx) { build(:octopus_energy_imported_trx, import_account: lloyds_account) }
        let(:lloyds_account) { Account.find_by_name('Lloyds Account') }

        specify { expect(import_matcher.match(octopus_energy_imported_trx)).to be true }
      end

      context 'when description is a regex' do
        subject(:import_matcher) { create(:import_matcher_amazon) }

        context('when it matches') do
          let(:amazon_imported_trx) { build(:amazon_imported_trx, import_account: lloyds_account) }
          let(:lloyds_account) { Account.find_by_name('Lloyds Account') }

          specify { expect(import_matcher.match(amazon_imported_trx)).to be true }
        end
      end
    end

    context 'when trx_type is nil' do
      subject(:import_matcher) { create(:import_matcher_octopus_energy, trx_type: nil) }

      context('when it matches') do
        let(:octopus_energy_imported_trx) { build(:octopus_energy_imported_trx, import_account: lloyds_account) }
        let(:lloyds_account) { Account.find_by_name('Lloyds Account') }

        specify { expect(import_matcher.match(octopus_energy_imported_trx)).to be true }
      end
    end
  end

  describe '#find_match' do
    subject!(:import_matcher) { create(:import_matcher_octopus_energy) }

    context 'when a match exists' do
      let(:octopus_energy_imported_trx) { build(:octopus_energy_imported_trx, import_account: lloyds_account) }
      let(:lloyds_account) { Account.find_by_name('Lloyds Account') }

      it "finds the match" do
        expect(ImportMatcher.find_match(octopus_energy_imported_trx)).to eq import_matcher
      end
    end
  end
end