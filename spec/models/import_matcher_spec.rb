require 'rails_helper'

RSpec.describe ImportMatcher, type: :model do
  describe 'validations' do
    it 'allows a rule with no counterparty, the category being the point of it' do
      expect(build(:import_matcher_without_counterparty)).to be_valid
    end

    it 'rejects a regex that will not compile, rather than letting it raise mid-import' do
      matcher = build(:import_matcher_amazon, description: 'AMAZON(')

      expect(matcher).not_to be_valid
      expect(matcher.errors[:description].first).to match(/not a valid regular expression/)
    end

    it 'accepts the same faulty pattern as a literal, where it is just text' do
      expect(build(:import_matcher_amazon, description: 'AMAZON(', description_is_regex: false)).to be_valid
    end

    it 'rejects a second rule for the same account, description and transaction type' do
      create(:import_matcher_octopus_energy)

      expect(build(:import_matcher_octopus_energy)).not_to be_valid
    end

    it 'allows the same description against a different transaction type' do
      create(:import_matcher_octopus_energy)

      expect(build(:import_matcher_octopus_energy, trx_type: 'DEB')).to be_valid
    end

    it 'allows the same description against a different account' do
      create(:import_matcher_octopus_energy)

      expect(build(:import_matcher_octopus_energy, account: create(:barclay_card_account))).to be_valid
    end
  end

  # A form sends "" for a field left empty.  Stored as typed, that would be a rule demanding an empty
  # transaction type, which no transaction has — the rule would silently never fire.
  describe 'a blank trx_type' do
    subject!(:import_matcher) { create(:import_matcher_octopus_energy, trx_type: "") }

    let(:lloyds_account) { Account.find_by_name('Lloyds Account') }

    it 'is stored as nil, meaning any transaction type' do
      expect(import_matcher.trx_type).to be_nil
    end

    it 'still matches a transaction that has one' do
      transaction = build(:octopus_energy_imported_trx, account: lloyds_account)

      expect(import_matcher.match(transaction)).to be true
    end
  end

  describe '#match' do
    context 'when account_id does not match' do
      subject(:import_matcher) { create(:import_matcher_octopus_energy) }

      let(:octopus_energy_imported_trx) { build(:octopus_energy_imported_trx, account: barclay_card_account) }
      let(:barclay_card_account) { create(:barclay_card_account) }

      specify { expect(import_matcher.match(octopus_energy_imported_trx)).to be false }
    end

    context 'when description is not regex' do
      subject(:import_matcher) { create(:import_matcher_octopus_energy) }

      context('when it matches') do
        let(:octopus_energy_imported_trx) { build(:octopus_energy_imported_trx, account: lloyds_account) }
        let(:lloyds_account) { Account.find_by_name('Lloyds Account') }

        specify { expect(import_matcher.match(octopus_energy_imported_trx)).to be true }
      end

      context 'when description is a regex' do
        subject(:import_matcher) { create(:import_matcher_amazon) }

        context('when it matches') do
          let(:amazon_imported_trx) { build(:amazon_imported_trx, account: lloyds_account) }
          let(:lloyds_account) { Account.find_by_name('Lloyds Account') }

          specify { expect(import_matcher.match(amazon_imported_trx)).to be true }
        end
      end
    end

    context 'when trx_type is nil' do
      subject(:import_matcher) { create(:import_matcher_octopus_energy, trx_type: nil) }

      context('when it matches') do
        let(:octopus_energy_imported_trx) { build(:octopus_energy_imported_trx, account: lloyds_account) }
        let(:lloyds_account) { Account.find_by_name('Lloyds Account') }

        specify { expect(import_matcher.match(octopus_energy_imported_trx)).to be true }
      end
    end
  end

  describe '#find_match' do
    subject!(:import_matcher) { create(:import_matcher_octopus_energy) }

    let(:lloyds_account) { Account.find_by_name('Lloyds Account') }

    context 'when a match exists' do
      let(:octopus_energy_imported_trx) { build(:octopus_energy_imported_trx, account: lloyds_account) }

      it "finds the match" do
        expect(ImportMatcher.find_match(octopus_energy_imported_trx)).to eq import_matcher
      end
    end

    context 'when nothing matches' do
      let(:salary_transaction) { build(:salary_transaction, account: lloyds_account) }

      it 'returns nil, leaving the transaction uncategorised' do
        expect(ImportMatcher.find_match(salary_transaction)).to be_nil
      end
    end

    context 'when the rule names a transaction type the transaction does not have' do
      let(:octopus_energy_imported_trx) do
        build(:octopus_energy_imported_trx, account: lloyds_account, trx_type: 'DEB')
      end

      it 'does not match' do
        expect(ImportMatcher.find_match(octopus_energy_imported_trx)).to be_nil
      end
    end

    # Which rule wins used to be whatever order the database returned.  A literal description is the more
    # specific claim, so it has to beat a regex however the two were created.
    context 'when both a regex rule and a literal rule match' do
      let(:amazon_imported_trx) { build(:amazon_imported_trx, account: lloyds_account) }

      let!(:regex_rule) { create(:import_matcher_amazon) }
      let!(:literal_rule) do
        create(:import_matcher_amazon, description: 'AMAZON* 204-813115', description_is_regex: false,
                                       category: Category.find_by(name: 'Travel'))
      end

      it 'prefers the literal one' do
        expect(ImportMatcher.find_match(amazon_imported_trx)).to eq literal_rule
      end

      it 'prefers it even when a matching regex rule was created afterwards' do
        later_regex = create(:import_matcher_amazon, description: 'AMAZON\*')

        # Both regex rules genuinely match, so this is precedence and not just an absence of competition.
        expect(regex_rule.match(amazon_imported_trx)).to be true
        expect(later_regex.match(amazon_imported_trx)).to be true

        expect(ImportMatcher.find_match(amazon_imported_trx)).to eq literal_rule
      end
    end
  end
end
