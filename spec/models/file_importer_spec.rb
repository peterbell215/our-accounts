require 'rails_helper'

RSpec.describe FileImporter, type: :class do
  before(:all) do
    LloydsImportFileGenerator.new.generate("lloyds_import_file.csv")
  end

  let(:lloyds_account) { Account.find_by_name("Lloyds Account") || FactoryBot.create(:lloyds_account) }

  it 'has generated a suitable test file' do
    expect(File.exist?(Rails.root.join('tmp', 'lloyds_import_file.csv'))).to be true
  end
end
