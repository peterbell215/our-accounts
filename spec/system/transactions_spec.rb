require 'rails_helper'

RSpec.describe "Transactions", type: :system do
  before(:all) do
    # Clear existing accounts to ensure a clean test environment
    Account.destroy_all

    # Create test account
    lloyds_account = FactoryBot.create(:lloyds_account)

    # Generate sample transaction data
    generator = AccountTrxDataGenerator.new(
      account: lloyds_account,
      import_columns_definition_factory: :lloyds_import_columns_definition
    )
    generator.generate
  end

  let(:account) { Account.find_by_name("Lloyds Account") }

  it "shows transactions on the index page" do
    # Visit the transactions index
    visit account_path(account)

    # We expect to see a table of transactions
    expect(page).to have_selector('#trx-div-table')
    expect(page).to have_selector('.div-table-row', minimum: 1)

    # Check for specific transaction details
    expect(page).to have_content('EMPLOYER CURRENT')
  end

  after(:all) do
    Account.destroy_all
  end
end
