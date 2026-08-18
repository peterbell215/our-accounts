require 'rails_helper'

RSpec.describe 'Import rules', type: :system do
  let(:account) { FactoryBot.create(:lloyds_account) }
  let!(:octopus) { FactoryBot.create(:octopus_energy) }

  # Reached from beside the transaction list, since noticing a row is filed wrongly is what sends you here.
  it 'is reachable from the account it belongs to' do
    visit account_path(account)

    click_link 'Manage Import Rules'

    expect(page).to have_content("Import rules for #{account.name}")
  end

  it 'allows a rule to be written by hand' do
    visit new_account_import_matcher_path(account)

    fill_in 'Description', with: 'OCTOPUS ENERGY'
    fill_in 'Transaction type', with: 'DD'
    select 'Utilities', from: 'Category'
    select 'Octopus Energy', from: 'Counterparty'

    click_button 'Create Import matcher'

    expect(page).to have_content('Rule was successfully created.')
    expect(page).to have_content('OCTOPUS ENERGY')

    matcher = account.import_matchers.sole
    expect(matcher.category.name).to eq 'Utilities'
    expect(matcher.counterparty).to eq octopus
    expect(matcher.trx_type).to eq 'DD'
    expect(matcher.description_is_regex).to be false
  end

  it 'allows a rule that categorises without naming a counterparty' do
    visit new_account_import_matcher_path(account)

    fill_in 'Description', with: 'O2'
    select 'Utilities', from: 'Category'
    # Counterparty left at "— none —".

    click_button 'Create Import matcher'

    expect(page).to have_content('Rule was successfully created.')
    expect(account.import_matchers.sole.counterparty).to be_nil
  end

  it 'leaves a blank transaction type meaning any type, rather than storing an empty one' do
    visit new_account_import_matcher_path(account)

    fill_in 'Description', with: 'OCTOPUS ENERGY'
    select 'Utilities', from: 'Category'

    click_button 'Create Import matcher'

    expect(page).to have_content('any')
    expect(account.import_matchers.sole.trx_type).to be_nil
  end

  it 'refuses a pattern that will not compile' do
    visit new_account_import_matcher_path(account)

    fill_in 'Description', with: 'OCTOPUS('
    check 'Treat as a pattern'
    select 'Utilities', from: 'Category'

    click_button 'Create Import matcher'

    expect(page).to have_content('is not a valid regular expression')
    expect(account.import_matchers).to be_empty
  end

  it 'shows how many transactions each rule has caught' do
    matcher = FactoryBot.create(:import_matcher_octopus_energy, account: account)
    FactoryBot.create(:tesco_shop, account: account, date: Date.new(2024, 7, 1),
                                   import_matcher: matcher)

    visit account_import_matchers_path(account)

    within("##{ActionView::RecordIdentifier.dom_id(matcher)}") do
      expect(page).to have_content('1')
    end
  end

  it 'narrows a long list of rules by description' do
    FactoryBot.create(:import_matcher_octopus_energy, account: account)
    FactoryBot.create(:import_matcher_amazon, account: account)

    visit account_import_matchers_path(account)
    expect(page).to have_content('OCTOPUS ENERGY')

    fill_in 'q', with: 'AMAZ'
    click_button 'Filter'

    expect(page).to have_content('AMAZON')
    expect(page).to have_no_content('OCTOPUS ENERGY')
  end

  it 'allows a rule to be edited' do
    matcher = FactoryBot.create(:import_matcher_octopus_energy, account: account)

    visit edit_account_import_matcher_path(account, matcher)

    select 'Travel', from: 'Category'
    click_button 'Update Import matcher'

    expect(page).to have_content('Rule was successfully updated.')
    expect(matcher.reload.category.name).to eq 'Travel'
  end
end
