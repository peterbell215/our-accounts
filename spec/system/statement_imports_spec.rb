require 'rails_helper'

RSpec.describe 'Importing a statement', type: :system do
  before(:all) do
    Account.destroy_all

    @lloyds_account = FactoryBot.create(:lloyds_account)
    FactoryBot.create(:lloyds_import_columns_definition)
    ImportTestHelpers.generate_test_file(@lloyds_account)
  end

  after(:all) do
    ImportTestHelpers.cleanup_test_file(@lloyds_account)
    Account.destroy_all
  end

  let(:account) { Account.find_by_name("Lloyds Account") }
  let(:statement) { ImportTestHelpers.get_filename_with_path(account) }

  def import_the_statement
    visit account_path(account)
    within('.show-actions') { click_link 'Import Statement' }
    attach_file 'csv_file', statement
    click_button 'Import'
  end

  it 'loads a statement from the account screen and shows the transactions it brought in' do
    import_the_statement

    expect(page).to have_content('Imported 17 transactions into Lloyds Account')
    expect(page).to have_current_path(account_path(account))
    expect(page).to have_content('TESCO STORES 2889')
  end

  # The everyday case: statements are downloaded by date range, and the ranges overlap.  Before this the
  # application would half-load the file and then refuse a balance, leaving an account to tidy up.
  it 'recognises a file it has already loaded rather than doubling the rows up' do
    import_the_statement
    import_the_statement

    expect(page).to have_content('All 17 rows in that file are already loaded')
    expect(account.transactions.count).to eq(17)
  end

  it 'refuses a statement that does not reconcile, and imports none of it' do
    account.update!(opening_balance: Money.from_amount(999.99))

    import_the_statement

    expect(page).to have_content('Nothing was imported.')
    expect(page).to have_content('the statement says the balance is')
    expect(account.transactions.count).to eq(0)
  end

  it 'explains itself on an account with no column layout, rather than failing' do
    ImportColumnsDefinition.find_by(account_id: account.id).destroy!

    visit account_path(account)
    within('.show-actions') { click_link 'Import Statement' }

    expect(page).to have_content('has no column layout yet')
    expect(page).to have_link('Describe its layout')
  end
end
