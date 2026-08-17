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
    let!(:octopus) { TradingAccount.find_by(name: "Octopus Energy") || FactoryBot.create(:octopus_energy_account) }

    def first_row
      find('form.transaction-row', match: :first)
    end

    it "shows the counterparty of a transaction that has one, and links to it" do
      transaction = account.transactions.newest_first.first
      transaction.update!(other_party: octopus)

      visit account_path(account)

      within(first_row) do
        expect(page).to have_field('transaction[other_party_name]', with: 'Octopus Energy')
        expect(page).to have_link(href: trading_account_path(octopus))
      end
    end

    it "leaves the field empty for a transaction with no counterparty" do
      visit account_path(account)

      within(first_row) do
        expect(page).to have_field('transaction[other_party_name]', with: '')
        expect(page).to have_no_link(href: %r{/trading_accounts/})
      end
    end

    it "links a counterparty typed into the row" do
      visit account_path(account)

      transaction_id = first_row['data-transaction-id'].to_i

      within(first_row) do
        fill_in 'transaction[other_party_name]', with: 'Octopus Energy'
        click_button 'save'
      end

      expect(page).to have_link(href: trading_account_path(octopus))
      expect(Transaction.find(transaction_id).other_party).to eq octopus
    end

    it "clears the counterparty when the field is emptied" do
      transaction = account.transactions.newest_first.first
      transaction.update!(other_party: octopus)

      visit account_path(account)

      within(first_row) do
        fill_in 'transaction[other_party_name]', with: ''
        click_button 'save'
      end

      expect(page).to have_no_link(href: trading_account_path(octopus))
      expect(transaction.reload.other_party).to be_nil
    end

    # Creating one on a typo would add to the sprawl of raw statement names the analysis import left behind.
    it "rejects a name no counterparty has, without creating one" do
      visit account_path(account)

      transaction_id = first_row['data-transaction-id'].to_i

      within(first_row) do
        fill_in 'transaction[other_party_name]', with: 'Ocotpus Enrgy'
        click_button 'save'
      end

      expect(page).to have_selector('input.field-error')
      expect(Transaction.find(transaction_id).other_party).to be_nil
      expect(TradingAccount.find_by(name: 'Ocotpus Enrgy')).to be_nil
    end

    it "offers the existing counterparties once for the whole page, not once per row" do
      visit account_path(account)

      expect(page).to have_selector('datalist#counterparty-names', visible: :all, count: 1)
      expect(page).to have_selector("datalist#counterparty-names option[value='Octopus Energy']",
                                    visible: :all)
    end
  end

  after(:all) do
    Account.destroy_all
  end
end
