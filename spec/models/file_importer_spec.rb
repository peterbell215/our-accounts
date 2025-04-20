require 'rails_helper'

RSpec.describe FileImporter, type: :class do
  FILENAME = "lloyds_import_file.csv"
  FILENAME_WITH_PATH = Rails.root.join('tmp', FILENAME)

  before(:all) do
    lloyds_account = FactoryBot.create(:lloyds_account)
    FactoryBot.create(:lloyds_import_columns_definition)

    AccountTrxDataGenerator.new(account: lloyds_account).generate(output: FILENAME_WITH_PATH)
  end

  let(:lloyds_account) { Account.find_by_name("Lloyds Account") }

  it 'has generated a suitable test file' do
    expect(File.exist?(FILENAME_WITH_PATH)).to be true
  end

  describe 'imports the generated file correctly' do
    subject!(:file_importer) { FileImporter.new(FILENAME_WITH_PATH, lloyds_account).import }

    specify { expect(lloyds_account.transactions.count).to eq(17) }
  end

  after(:all) do
    FileUtils.rm_f(FILENAME_WITH_PATH)
    Account.destroy_all
  end
end
