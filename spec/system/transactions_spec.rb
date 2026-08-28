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
      # Amber rather than red: the row is asking, not refusing.
      expect(page).to have_selector('input.field-pending')
      expect(first_row).to have_button('save', title: 'Create "Bristol Water" and save')
      expect(Counterparty.find_by(name: 'Bristol Water')).to be_nil

      # The border and the tooltip are not enough on their own — the question has to be in words somewhere
      # the reader is actually looking.
      within('#transaction-message') do
        expect(page).to have_selector('.row-question', text: /Bristol Water.*is not a counterparty yet/)
        expect(page).to have_text('Your other edits to the row are held')
      end

      within(first_row) { click_button 'save' }

      expect(page).to have_link(href: %r{/counterparties/\d+})
      water = Counterparty.find_by!(name: 'Bristol Water')
      expect(Transaction.find(transaction_id).counterparty).to eq water
      expect(page).to have_selector("datalist#counterparty-names option[value='Bristol Water']",
                                    visible: :all)

      # A question the reader has answered must not stay on the screen.
      expect(page).to have_no_selector('#transaction-message .row-question')
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

      # Red, and worded so the reader knows the rest of the row is waiting rather than lost.
      within('#transaction-message') do
        expect(page).to have_selector('.row-error', text: /Lloyds Account.*is one of your own accounts/)
        expect(page).to have_text('Change the name to save the row')
      end
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

  # Rules used to have to be written from scratch on the rules screen, with the description retyped by hand.
  # The row the reader noticed is the obvious place to start one from.
  describe "making a rule from a row" do
    let!(:octopus) { Counterparty.find_by(name: "Octopus Energy") || FactoryBot.create(:octopus_energy) }
    let(:newest) { account.transactions.newest_first.first }

    def first_row
      find('form.transaction-row', match: :first)
    end

    it "opens the rules form already filled in from the row" do
      visit account_path(account)

      within(first_row) do
        expect(find_link('rule')[:title]).to eq(%(Create an import rule from "#{newest.description}"))
        click_link 'rule'
      end

      expect(page).to have_field('Description', with: newest.description)
    end

    # nil means "any transaction type", which is nearly always what is wanted, so the type the one example
    # happened to carry is deliberately left behind.
    it "leaves the transaction type blank" do
      visit account_path(account)

      within(first_row) { click_link 'rule' }

      expect(page).to have_field('Transaction type', with: '')
      expect(page).to have_unchecked_field('Treat as a pattern')
    end

    it "carries the row's category and counterparty across" do
      newest.update!(category: Category.find_by!(name: 'Travel'), counterparty: octopus)

      visit account_path(account)

      within(first_row) { click_link 'rule' }

      expect(page).to have_select('Category', selected: 'Travel')
      expect(page).to have_select('Counterparty', selected: 'Octopus Energy')
    end

    # Leaving the page would throw the confirmation away, and the name it offered is not a record yet, so
    # there would be no counterparty to carry into the rule either.
    it "offers nothing while a counterparty is waiting to be confirmed" do
      visit account_path(account)

      within(first_row) do
        fill_in 'transaction[counterparty_name]', with: 'Bristol Water'
        click_button 'save'
      end

      expect(page).to have_selector('input.field-pending')

      within(first_row) do
        expect(page).to have_no_link('rule')
        expect(page).to have_button('save')
      end
    end

    it "offers nothing on a row that has never been saved" do
      visit account_path(account)

      click_link 'Add New Transaction'

      within('#new_transaction') { expect(page).to have_no_link('rule') }
    end
  end

  after(:all) do
    Account.destroy_all
  end
end
