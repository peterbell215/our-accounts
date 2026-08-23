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

  # The reason the whole feature exists: GITHUB INC. arrives monthly, four of them sat uncategorised, and a
  # rule written on this screen used only to affect the next import.
  describe 'made from a transaction row' do
    let!(:subscriptions) { FactoryBot.create(:subscriptions_category) }

    def github_rows(count = 4, **attributes)
      Array.new(count) do |month|
        FactoryBot.create(:github_subscription, account: account,
                                                date: Date.new(2024, 9, 12) + month.months, **attributes)
      end
    end

    it 'catches the rest of that history, not just the next import' do
      rows = github_rows

      visit account_path(account)
      within(find('form.transaction-row', match: :first)) { click_link 'rule' }

      expect(page).to have_field('Description', with: 'GITHUB INC.')
      select 'Subscriptions', from: 'Category'
      click_button 'Create Import matcher'

      expect(page).to have_content('It also categorised 4 transactions already imported.')

      matcher = account.import_matchers.sole
      expect(rows.map { |row| row.reload.category }).to all eq subscriptions
      expect(rows.map { |row| row.reload.import_matcher_id }).to all eq matcher.id

      # The Matched column is the sixth, and it is the count the reader has to be able to trust.
      within("#import_matcher_#{matcher.id}") { expect(all('.div-table-col')[5]).to have_content('4') }
    end

    # Hand judgement wins, so the row somebody categorised themselves keeps its category, stays unclaimed by
    # the rule, and is not counted.  That is why the Matched count can read one lower than the number of
    # transactions sharing a description.
    it 'leaves a transaction categorised by hand out of it' do
      by_hand = github_rows(1, category: Category.find_by!(name: 'Travel')).first
      github_rows(2)

      visit new_account_import_matcher_path(account, import_matcher: { description: 'GITHUB INC.' })
      select 'Subscriptions', from: 'Category'
      click_button 'Create Import matcher'

      expect(page).to have_content('It also categorised 2 transactions already imported.')
      expect(by_hand.reload.category.name).to eq 'Travel'
      expect(by_hand.import_matcher_id).to be_nil
    end

    it 'says nothing about existing transactions when it caught none' do
      visit new_account_import_matcher_path(account, import_matcher: { description: 'GITHUB INC.' })
      select 'Subscriptions', from: 'Category'
      click_button 'Create Import matcher'

      expect(page).to have_content('Rule was successfully created.')
      expect(page).to have_no_content('already imported')
    end
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
