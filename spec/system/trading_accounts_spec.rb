require 'rails_helper'

RSpec.describe 'Counterparties', type: :system do
  it 'allows a counterparty to be created' do
    visit new_trading_account_path

    fill_in 'Name', with: 'Thames Water'
    click_button 'Create Trading account'

    expect(page).to have_content('Counterparty was successfully created.')
    expect(page).to have_content('Thames Water')
    expect(TradingAccount.find_by(name: 'Thames Water')).to be_present
  end

  # The reason these screens exist: AnalysisImporter names counterparties after raw statement text.
  it 'allows a counterparty derived from statement text to be renamed' do
    counterparty = FactoryBot.create(:trading_account, name: 'TESCO STORES 2889')

    visit edit_trading_account_path(counterparty)

    fill_in 'Name', with: 'Tesco'
    click_button 'Update Trading account'

    expect(page).to have_content('Counterparty was successfully updated.')
    expect(counterparty.reload.name).to eq 'Tesco'
  end

  it 'explains a name one of the household’s accounts already holds' do
    FactoryBot.create(:lloyds_account)

    visit new_trading_account_path

    fill_in 'Name', with: 'Lloyds Account'
    click_button 'Create Trading account'

    expect(page).to have_content('has already been taken')
  end

  # This is the whole point of modelling a counterparty as an account: one place showing every dealing with
  # a vendor, whichever account paid for it.
  it 'gathers a vendor’s transactions from every account' do
    octopus = FactoryBot.create(:octopus_energy_account)
    FactoryBot.create(:tesco_shop, account: FactoryBot.create(:lloyds_account), other_party: octopus,
                                   date: Date.new(2024, 7, 1), description: 'PAID FROM CURRENT')
    FactoryBot.create(:tesco_shop, account: FactoryBot.create(:barclay_card_account), other_party: octopus,
                                   date: Date.new(2024, 7, 2), description: 'PAID FROM CARD')

    visit trading_account_path(octopus)

    expect(page).to have_content('PAID FROM CURRENT')
    expect(page).to have_content('PAID FROM CARD')
    expect(page).to have_content('Lloyds Account')
    expect(page).to have_content('Barclaycard')
    expect(page).to have_content('2 transactions')
  end

  it 'lists the rules that name it, so an unused counterparty is obvious' do
    octopus = FactoryBot.create(:octopus_energy_account)

    visit trading_account_path(octopus)
    expect(page).to have_content('No import rule names this counterparty')

    FactoryBot.create(:import_matcher_octopus_energy, other_party: octopus)

    visit trading_account_path(octopus)
    expect(page).to have_content('OCTOPUS ENERGY')
  end

  it 'orders the list so the vendors most is spent with come first' do
    small = FactoryBot.create(:trading_account, name: 'Corner Shop')
    large = FactoryBot.create(:trading_account, name: 'Big Supermarket')
    account = FactoryBot.create(:lloyds_account)

    FactoryBot.create(:tesco_shop, account: account, other_party: small, date: Date.new(2024, 7, 1),
                                   amount: Money.from_amount(-5.00))
    FactoryBot.create(:tesco_shop, account: account, other_party: large, date: Date.new(2024, 7, 2),
                                   amount: Money.from_amount(-500.00))

    visit trading_accounts_path

    names = page.all('#trading_accounts tbody tr td:first-child').map(&:text)
    expect(names).to eq([ 'Big Supermarket', 'Corner Shop' ])
  end

  it 'keeps the transactions when a counterparty is deleted' do
    octopus = FactoryBot.create(:octopus_energy_account)
    transaction = FactoryBot.create(:tesco_shop, account: FactoryBot.create(:lloyds_account),
                                                 other_party: octopus, date: Date.new(2024, 7, 1))

    visit trading_account_path(octopus)
    accept_confirm { click_button 'Destroy this counterparty' }

    expect(page).to have_content('Counterparty was successfully destroyed.')
    expect(transaction.reload).to be_present
    expect(transaction.other_party).to be_nil
  end
end
