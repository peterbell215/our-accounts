require 'rails_helper'

RSpec.describe FileImporter, type: :class do
  describe 'Lloyds Import' do
    before(:all) do
      # Create Lloyds test data
      @lloyds_account = FactoryBot.create(:lloyds_account)
      FactoryBot.create(:lloyds_import_columns_definition)
      ImportTestHelpers.generate_test_file(@lloyds_account)
    end

    after(:all) do
      ImportTestHelpers.cleanup_test_file(@lloyds_account)
      Account.destroy_all
    end

    let(:lloyds_account) { Account.find_by_name("Lloyds Account") }
    let(:lloyds_filename) { ImportTestHelpers.get_filename_with_path(lloyds_account) }

    it 'has generated a suitable test file' do
      expect(File.exist?(lloyds_filename)).to be true
    end

    describe 'imports the generated file correctly' do
      subject!(:file_importer) { FileImporter.new(lloyds_filename, lloyds_account).import }

      specify { expect(lloyds_account.transactions.count).to eq(17) }
    end
  end

  describe 'Barclaycard Import' do
    before(:all) do
      # Create Barclaycard test data
      @barclaycard_account = FactoryBot.create(:barclay_card_account)
      FactoryBot.create(:barclaycard_import_columns_definition)
      ImportTestHelpers.generate_test_file(@barclaycard_account)
    end

    after(:all) do
      ImportTestHelpers.cleanup_test_file(@barclaycard_account)
      Account.destroy_all
    end

    let(:barclaycard_account) { Account.find_by_name("Barclaycard") }
    let(:barclaycard_filename) { ImportTestHelpers.get_filename_with_path(barclaycard_account) }

    it 'has generated a suitable test file' do
      expect(File.exist?(barclaycard_filename)).to be true
    end

    describe 'imports the generated file correctly' do
      subject!(:file_importer) { FileImporter.new(barclaycard_filename, barclaycard_account).import }
      specify { expect(barclaycard_account.transactions.count).to eq(17) }
    end
  end
end
