require 'rails_helper'

RSpec.describe 'The forecast', type: :system do
  let!(:data) { ForecastDataBuilder.new(today: Date.current).build }

  let(:this_month) { Date.current.to_fs(:month_year) }

  it 'is reached from the menu bar' do
    visit root_path

    click_link 'Forecast'

    expect(page).to have_content("Forecast for #{this_month}")
  end

  it 'shows every category with what it will cost and what has gone already' do
    visit forecast_path

    within('#forecast') do
      expect(page).to have_content('Food')
      expect(page).to have_content('Subscriptions')
      expect(page).to have_content('Uncategorised')
      expect(page).to have_content('Total')
    end
  end

  it 'says which hand-forecast categories are still waiting for a figure' do
    visit forecast_path

    expect(page).to have_selector('#awaiting_figures', text: 'Holidays')
  end

  it 'says which categories are deliberately left out' do
    visit forecast_path

    expect(page).to have_selector('#excluded_categories', text: 'Transfers')
  end

  describe 'moving between months' do
    it 'steps back a month and offers the way home again' do
      visit forecast_path

      click_link "« #{(Date.current << 1).to_fs(:month_year)}"

      expect(page).to have_content("Forecast for #{(Date.current << 1).to_fs(:month_year)}")

      click_link 'jump to this month'

      expect(page).to have_content("Forecast for #{this_month}")
    end

    # Before the first transaction there is nothing to forecast from, so the button says so rather than
    # taking the reader somewhere empty.
    it 'disables the way back at the first month there is any history for' do
      visit forecast_path(month: Transaction.minimum(:date).to_fs(:iso8601))

      expect(page).to have_selector('span.pure-button-disabled', text: '«')
    end

    it 'disables the way forward a year out' do
      visit forecast_path(month: (Date.current >> 12).to_fs(:iso8601))

      expect(page).to have_selector('span.pure-button-disabled', text: '»')
    end
  end

  describe 'the workings behind a line' do
    it 'lists the months an averaged category is averaged over' do
      visit forecast_path

      click_link 'Food'

      expect(page).to have_content('The months it is averaged over')
      expect(page).to have_selector('#window_months tbody tr', count: 6)
    end

    # The mechanism the whole feature turns on: seeing which bills have gone and which have not.
    it 'ticks the regular payments that have already gone out, and not the ones still due' do
      # Octopus is paid on the 19th; the water bill is quarterly and not due this month.
      create(:transaction, account: data.account, category: data.subscriptions, counterparty: data.energy,
                           date: Date.current.beginning_of_month, description: 'OCTOPUS ENERGY',
                           trx_type: 'DD', amount: Money.from_amount(-218.85))

      visit forecast_path

      click_link 'Subscriptions'

      within('#regular_payments') do
        expect(page).to have_content('Octopus Energy')
        expect(page).to have_content('✓')
      end
    end

    it 'explains why an excluded category has no figures' do
      visit forecast_path

      click_link 'Transfers'

      expect(page).to have_content('count the same money twice')
    end
  end

  describe 'a figure entered by hand' do
    it 'is saved, counted in the total, and can be withdrawn again' do
      visit forecast_path

      click_link 'not set'

      fill_in 'Expected spend (£)', with: '800.00'
      click_button 'Save prediction'

      expect(page).to have_content('Prediction saved.')
      expect(ManualForecast.last.amount).to eq(Money.from_amount(800.00))

      click_link 'Back'

      within('#forecast') { expect(page).to have_content('£800.00') }
      expect(page).not_to have_selector('#awaiting_figures')

      click_link 'Holidays'
      fill_in 'Expected spend (£)', with: ''
      click_button 'Save prediction'

      expect(page).to have_content('Prediction cleared.')
      expect(ManualForecast.count).to be_zero
    end
  end

  describe 'changing how a category is predicted' do
    it 'is one click from the forecast, and changes what the forecast says' do
      visit forecast_path

      within("#forecast") { click_link 'An average of recent months', match: :first }

      select 'Not forecast', from: 'Predict this by'
      click_button 'Update Category'

      visit forecast_path

      expect(page).to have_selector('#excluded_categories')
    end
  end
end
