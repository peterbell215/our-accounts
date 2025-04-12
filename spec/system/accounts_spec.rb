# spec/system/accounts_spec.rb
require 'rails_helper'

RSpec.describe 'Creating a new account', type: :system do
  it 'allows a user to create a new account' do
    # Visit the new account page
    visit new_account_path

    # Select the account type
    select 'Bank Account', from: 'type'

    # Fill in the form fields
    fill_in 'Name', with: 'Test Account'
    fill_in 'Account number', with: '12345678'
    fill_in 'Sortcode', with: '12-34-56'
    fill_in 'Opening balance', with: '1000.00'
    fill_in 'Opening date', with: '2023-01-01'

    # Submit the form
    click_button 'Create Account'

    # Verify the account was created successfully
    expect(page).to have_content('Account was successfully created.')
    expect(page).to have_content('Test Account')

    check_account_creation
  end

  it 'allows a user to create a Credit Card account and hides the sortcode field' do
    # Visit the new account page
    visit new_account_path

    # Select the account type
    select 'Credit Card', from: 'type'

    # Verify that the sortcode field is not visible
    expect(page).not_to have_field('Sortcode')

    # Fill in the form fields
    fill_in 'Name', with: 'Test Credit Card'
    fill_in 'Account number', with: '0000-0000-0000-0000'
    fill_in 'Opening balance', with: '500.00'
    fill_in 'Opening date', with: '2023-01-01'

    # Submit the form
    click_button 'Create Account'

    # Verify the account was created successfully
    expect(page).to have_content('Account was successfully created.')
    expect(page).to have_content('Test Credit Card')
  end

  it 'flags an error if no name is entered' do
    # Visit the new account page
    visit new_account_path

    # Select the account type
    select 'Bank Account', from: 'type'

    # Fill in the form fields, leaving the name blank
    fill_in 'Name', with: ''
    fill_in 'Account number', with: '12345678'
    fill_in 'Sortcode', with: '12-34-56'
    fill_in 'Opening balance', with: '1000.00'
    fill_in 'Opening date', with: '2023-01-01'

    # Submit the form
    click_button 'Create Account'

    # Verify that an error message is displayed
    expect(page).to have_content("Name can't be blank")
  end

  it 'renders the account details correctly' do
    # Create a test account in the database
    account = FactoryBot.create(:lloyds_account)

    # Visit the account show page
    visit account_path(account)

    # Verify that the account details are displayed correctly
    expect(page).to have_content('Lloyds Account')
    expect(page).to have_content('01234567')
    expect(page).to have_content('30-00-00')
    expect(page).to have_content('£1,000.00')
    expect(page).to have_content('3 January 2023')
  end

  def check_account_creation
    # Verify the record was written to the database
    account = Account.find_by(name: 'Test Account')
    expect(account).not_to be_nil
    expect(account.account_number).to eq('12345678')
    expect(account.sortcode).to eq('12-34-56')
    expect(account.opening_balance).to eq(Money.from_amount(1000.00))
  end
end
