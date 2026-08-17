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

  it "allows changing a transaction's category" do
    # Visit the account page
    visit account_path(account)

    # Get the first transaction's ID to verify database changes later
    first_transaction_row = find('form.transaction-row', match: :first)
    transaction_id = first_transaction_row['data-transaction-id'].to_i

    # Find and change the category dropdown to 'Travel' for the first transaction
    within(first_transaction_row) do
      select 'Travel', from: 'transaction[category_id]'
      click_button 'save'
    end

    sleep 10

    # Verify the UI shows the updated category
    within(first_transaction_row) do
      expect(page).to have_select('transaction[category_id]', selected: 'Travel')
    end

    # Verify the database record has been updated
    transaction = Transaction.find(transaction_id)
    expect(transaction.category.name).to eq('Travel')
  end

  describe "the save button" do
    before { visit account_path(account) }

    let(:row) { find('form.transaction-row', match: :first) }

    it "is out of the way until the row has an edit to save" do
      within(row) { expect(page).to have_no_button('save') }
    end

    it "appears once the category is changed" do
      within(row) do
        select 'Travel', from: 'transaction[category_id]'

        expect(page).to have_button('save')
      end
    end

    it "goes away again when the row is put back as it was" do
      within(row) do
        expect(find('select').value).to eq('') # the generated transactions arrive uncategorised

        select 'Travel', from: 'transaction[category_id]'
        expect(page).to have_button('save')

        find('option[value=""]').select_option

        expect(page).to have_no_button('save')
      end
    end

    it "is offered straight away on a row that has never been saved" do
      click_link 'Add New Transaction'

      within('#new_transaction') { expect(page).to have_button('save') }
    end

    it "explains itself, as does the delete button beside it" do
      within(row) do
        select 'Travel', from: 'transaction[category_id]'

        expect(find_button('save')[:title]).to eq('Save Transaction')
        expect(find_link('delete')[:title]).to eq('Delete Transaction')
      end
    end
  end

  after(:all) do
    Account.destroy_all
  end
end
