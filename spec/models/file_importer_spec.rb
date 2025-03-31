require 'rails_helper'

RSpec.describe FileImporter, type: :class do
  FILENAME = "lloyds_import_file.csv"
  FILENAME_WITH_PATH = Rails.root.join('tmp', FILENAME)

  before(:all) { LloydsImportFileGenerator.new.generate(FILENAME) }

  let(:lloyds_account) { Account.find_by_name("Lloyds Account") || FactoryBot.create(:lloyds_account) }

  it 'has generated a suitable test file' do
    expect(File.exist?(FILENAME_WITH_PATH)).to be true
  end

  describe 'imports the generated file correctly' do
    subject!(:file_importer) { FileImporter.new(FILENAME_WITH_PATH, lloyds_account).import }

    specify { expect(lloyds_account.transactions.count).to eq(17) }
  end
end
