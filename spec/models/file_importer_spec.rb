require 'rails_helper'

RSpec.describe FileImporter, type: :class do
  before(:all) do
    lloyds_account = FactoryBot.create(:lloyds_account)
    FactoryBot.create(:lloyds_import_columns_definition)

    ImportTestHelpers.generate_test_file(lloyds_account)
  end

  let(:lloyds_account) { Account.find_by_name("Lloyds Account") }

  it 'has generated a suitable test file' do
    expect(File.exist?(ImportTestHelpers::FILENAME_WITH_PATH)).to be true
  end

  describe 'imports the generated file correctly' do
    subject!(:file_importer) { FileImporter.new(ImportTestHelpers::FILENAME_WITH_PATH, lloyds_account).import }

    specify { expect(lloyds_account.transactions.count).to eq(17) }
  end

  after(:all) do
    ImportTestHelpers.cleanup_test_file
    Account.destroy_all
  end
end
