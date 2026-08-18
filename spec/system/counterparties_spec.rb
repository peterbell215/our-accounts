require 'rails_helper'

RSpec.describe 'Counterparties', type: :system do
  it 'allows a counterparty to be created' do
    visit new_counterparty_path

    fill_in 'Name', with: 'Thames Water'
    click_button 'Create Counterparty'

    expect(page).to have_content('Counterparty was successfully created.')
    expect(page).to have_content('Thames Water')
    expect(Counterparty.find_by(name: 'Thames Water')).to be_present
  end

  # The reason these screens exist: AnalysisImporter names counterparties after raw statement text.
  it 'allows a counterparty derived from statement text to be renamed' do
    counterparty = FactoryBot.create(:counterparty, name: 'TESCO STORES 2889')

    visit edit_counterparty_path(counterparty)

    fill_in 'Name', with: 'Tesco'
    click_button 'Update Counterparty'

    expect(page).to have_content('Counterparty was successfully updated.')
    expect(counterparty.reload.name).to eq 'Tesco'
  end

  it 'explains a name one of the household’s accounts already holds' do
    FactoryBot.create(:lloyds_account)

    visit new_counterparty_path

    fill_in 'Name', with: 'Lloyds Account'
    click_button 'Create Counterparty'

    expect(page).to have_content('has already been taken')
  end

  # This is the whole point of modelling a counterparty as an account: one place showing every dealing with
  # a vendor, whichever account paid for it.
  it 'gathers a vendor’s transactions from every account' do
    octopus = FactoryBot.create(:octopus_energy)
    FactoryBot.create(:tesco_shop, account: FactoryBot.create(:lloyds_account), counterparty: octopus,
                                   date: Date.new(2024, 7, 1), description: 'PAID FROM CURRENT')
    FactoryBot.create(:tesco_shop, account: FactoryBot.create(:barclay_card_account), counterparty: octopus,
                                   date: Date.new(2024, 7, 2), description: 'PAID FROM CARD')

    visit counterparty_path(octopus)

    expect(page).to have_content('PAID FROM CURRENT')
    expect(page).to have_content('PAID FROM CARD')
    expect(page).to have_content('Lloyds Account')
    expect(page).to have_content('Barclaycard')
    expect(page).to have_content('2 transactions')
  end

  it 'lists the rules that name it, so an unused counterparty is obvious' do
    octopus = FactoryBot.create(:octopus_energy)

    visit counterparty_path(octopus)
    expect(page).to have_content('No import rule names this counterparty')

    FactoryBot.create(:import_matcher_octopus_energy, counterparty: octopus)

    visit counterparty_path(octopus)
    expect(page).to have_content('OCTOPUS ENERGY')
  end

  describe 'ordering the list' do
    # Named so that alphabetical order and spend order disagree.
    let!(:small) { FactoryBot.create(:counterparty, name: 'Anvil Works') }
    let!(:large) { FactoryBot.create(:counterparty, name: 'Zebra Supplies') }
    let(:account) { FactoryBot.create(:lloyds_account) }

    before do
      FactoryBot.create(:tesco_shop, account: account, counterparty: small, date: Date.new(2024, 7, 1),
                                     amount: Money.from_amount(-5.00))
      FactoryBot.create(:tesco_shop, account: account, counterparty: large, date: Date.new(2024, 7, 2),
                                     amount: Money.from_amount(-500.00))
      visit counterparties_path
    end

    # Reading every cell would snapshot the old rows and go stale the moment a click reloads the page, so
    # wait for the row that should now be first before comparing the whole order.
    def expect_order(expected)
      expect(page).to have_selector('#counterparties tbody tr:first-child td:first-child',
                                    text: expected.first)
      expect(page.all('#counterparties tbody tr td:first-child').map(&:text)).to eq(expected)
    end

    it 'is alphabetical to begin with, so a name can be found' do
      expect_order([ 'Anvil Works', 'Zebra Supplies' ])
    end

    it 'reverses when the same heading is clicked again' do
      click_link 'Name'

      expect_order([ 'Zebra Supplies', 'Anvil Works' ])
    end

    it 'puts the vendors most is spent with first when ordered by total' do
      click_link 'Total'

      expect_order([ 'Zebra Supplies', 'Anvil Works' ])
    end

    it 'marks which column the order is on' do
      expect(page).to have_link('Name ▲')

      click_link 'Name ▲'

      expect(page).to have_link('Name ▼')
    end
  end

  it 'keeps the transactions when a counterparty is deleted' do
    octopus = FactoryBot.create(:octopus_energy)
    transaction = FactoryBot.create(:tesco_shop, account: FactoryBot.create(:lloyds_account),
                                                 counterparty: octopus, date: Date.new(2024, 7, 1))

    visit counterparty_path(octopus)
    accept_confirm { click_button 'Destroy' }

    expect(page).to have_content('Counterparty was successfully destroyed.')
    expect(transaction.reload).to be_present
    expect(transaction.counterparty).to be_nil
  end
end
