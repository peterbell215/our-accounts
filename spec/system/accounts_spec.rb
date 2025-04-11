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
  end
end
