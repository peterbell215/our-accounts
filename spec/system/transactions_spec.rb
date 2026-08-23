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

  describe "the counterparty column" do
    let!(:octopus) { Counterparty.find_by(name: "Octopus Energy") || FactoryBot.create(:octopus_energy) }

    def first_row
      find('form.transaction-row', match: :first)
    end

    it "shows the counterparty of a transaction that has one, and links to it" do
      transaction = account.transactions.newest_first.first
      transaction.update!(counterparty: octopus)

      visit account_path(account)

      within(first_row) do
        expect(page).to have_field('transaction[counterparty_name]', with: 'Octopus Energy')
        expect(page).to have_link(href: counterparty_path(octopus))
      end
    end

    it "leaves the field empty for a transaction with no counterparty" do
      visit account_path(account)

      within(first_row) do
        expect(page).to have_field('transaction[counterparty_name]', with: '')
        expect(page).to have_no_link(href: %r{/counterparties/})
      end
    end

    it "links a counterparty typed into the row" do
      visit account_path(account)

      transaction_id = first_row['data-transaction-id'].to_i

      within(first_row) do
        fill_in 'transaction[counterparty_name]', with: 'Octopus Energy'
        click_button 'save'
      end

      expect(page).to have_link(href: counterparty_path(octopus))
      expect(Transaction.find(transaction_id).counterparty).to eq octopus
    end

    it "clears the counterparty when the field is emptied" do
      transaction = account.transactions.newest_first.first
      transaction.update!(counterparty: octopus)

      visit account_path(account)

      within(first_row) do
        fill_in 'transaction[counterparty_name]', with: ''
        click_button 'save'
      end

      expect(page).to have_no_link(href: counterparty_path(octopus))
      expect(transaction.reload.counterparty).to be_nil
    end

    # Creating one on the first save would let a typo add to the sprawl of raw statement names the analysis
    # import left behind.  The second save is the guard that used to be an outright refusal.
    it "creates a counterparty the second time an unknown name is saved" do
      visit account_path(account)

      transaction_id = first_row['data-transaction-id'].to_i

      within(first_row) do
        fill_in 'transaction[counterparty_name]', with: 'Bristol Water'
        click_button 'save'
      end

      # The save button has to survive the rejection, or there is nothing left to press: nothing on the row
      # looks edited once the server has rendered the typed name back as the field's own default.
      expect(page).to have_selector('input.field-error')
      expect(first_row).to have_button('save', title: 'Create "Bristol Water" and save')
      expect(Counterparty.find_by(name: 'Bristol Water')).to be_nil

      within(first_row) { click_button 'save' }

      expect(page).to have_link(href: %r{/counterparties/\d+})
      water = Counterparty.find_by!(name: 'Bristol Water')
      expect(Transaction.find(transaction_id).counterparty).to eq water
      expect(page).to have_selector("datalist#counterparty-names option[value='Bristol Water']",
                                    visible: :all)
    end

    # The row hands back the name it offered rather than a bare yes, so a correction is asked about in its
    # turn instead of the typo being created behind the reader.
    it "asks again when the name is corrected before the second save" do
      visit account_path(account)

      within(first_row) do
        fill_in 'transaction[counterparty_name]', with: 'Bristol Watr'
        click_button 'save'
      end

      expect(first_row).to have_button('save', title: 'Create "Bristol Watr" and save')

      within(first_row) do
        fill_in 'transaction[counterparty_name]', with: 'Bristol Water'
        click_button 'save'
      end

      expect(first_row).to have_button('save', title: 'Create "Bristol Water" and save')
      expect(Counterparty.where(name: [ 'Bristol Watr', 'Bristol Water' ])).to be_empty
    end

    # Account names are case-insensitively unique across the whole STI table, so there is nothing to offer,
    # and no save button either: pressing it again could only fail again.  Editing the field brings it back.
    it "refuses one of the household's own account names outright" do
      visit account_path(account)

      within(first_row) do
        fill_in 'transaction[counterparty_name]', with: 'Lloyds Account'
        click_button 'save'
      end

      expect(page).to have_selector('input.field-error')
      expect(first_row).to have_no_button('save')
    end

    it "offers the existing counterparties once for the whole page, not once per row" do
      visit account_path(account)

      expect(page).to have_selector('datalist#counterparty-names', visible: :all, count: 1)
      expect(page).to have_selector("datalist#counterparty-names option[value='Octopus Energy']",
                                    visible: :all)
    end
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
