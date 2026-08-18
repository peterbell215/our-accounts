require 'rails_helper'

describe Account, type: :model do
  describe 'bank account' do
    subject(:lloyds_account) { FactoryBot.create(:lloyds_account) }

    let(:first_lloyds_transaction) { FactoryBot.build(:first_lloyds_transaction) }
    let(:second_lloyds_transaction) { FactoryBot.build(:second_lloyds_transaction) }

    context
  end

  # Names are typed on the counterparties screen and matched against text typed into a transaction row, so
  # they are stored squished and treated as case-insensitively unique — otherwise a name could fail to
  # match itself, or two names differing only in case could both exist for the lookup to pick between.
  describe 'name' do
    it 'is stored without surrounding or doubled space' do
      expect(create(:octopus_energy, name: "  Octopus   Energy  ").name).to eq "Octopus Energy"
    end

    it 'is found by a name typed with stray space, the query being normalised too' do
      octopus = create(:octopus_energy, name: "Octopus Energy")

      expect(Counterparty.find_by(name: " Octopus  Energy ")).to eq octopus
    end

    it 'rejects a second account whose name differs only in case' do
      create(:octopus_energy, name: "Octopus Energy")

      expect(build(:octopus_energy, name: "OCTOPUS ENERGY")).not_to be_valid
    end

    it 'still rejects a name shorter than three characters' do
      expect(build(:octopus_energy, name: "O2")).not_to be_valid
    end
  end
end
