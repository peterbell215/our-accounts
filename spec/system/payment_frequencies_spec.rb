require 'rails_helper'

RSpec.describe 'Setting a payment frequency by hand', type: :system do
  let!(:data) { ForecastDataBuilder.new(today: Date.current).build }

  # A direct debit paid once, last month: the case the detector cannot read and the reader can.  Placed in
  # a completed month, because the amount is always the most recent occurrence and this month has not
  # finished.
  let!(:new_direct_debit) do
    create(:transaction, account: data.account, category: data.subscriptions,
                         date: (Date.current.beginning_of_month << 1).change(day: 12),
                         description: "NEW BROADBAND CO", trx_type: "DD",
                         amount: Money.from_amount(-49.00))
  end

  def visit_frequencies = visit edit_category_path(data.subscriptions)

  it 'lists every payee the forecast found, and why each is or is not counted' do
    visit_frequencies

    within('#payment_frequencies') do
      expect(page).to have_content('Octopus Energy')
      expect(page).to have_content('South Staffs Water')
      expect(page).to have_content('NEW BROADBAND CO')
      expect(page).to have_content('ANCIENT STREAMING CO')
    end
  end

  it 'says why a payee seen only once is left out, and how to fix it' do
    visit_frequencies

    expect(page).to have_content('seen only once before this month')
  end

  it 'says why a payee that has gone quiet is left out' do
    visit_frequencies

    expect(page).to have_content('nothing since')
  end

  # The headline journey: name the frequency of a direct debit the history could not read, and watch it
  # appear in the month's total.
  it 'brings a payee seen only once into the forecast' do
    before_setting = Forecast::Month.new(month: Date.current).expected

    visit_frequencies
    select 'Monthly', from: 'How often NEW BROADBAND CO is paid'
    click_button 'Save frequencies'

    expect(page).to have_content('Payment frequencies saved.')
    expect(page).to have_content('Yes — at the frequency you set')

    expect(Forecast::Month.new(month: Date.current).expected)
      .to eq(before_setting + Money.from_amount(49.00))
  end

  it 'takes a payee out of the forecast when it is not a regular payment' do
    before_setting = Forecast::Month.new(month: Date.current).expected

    visit_frequencies
    select 'Not a regular payment', from: 'How often Octopus Energy is paid'
    click_button 'Save frequencies'

    expect(page).to have_content('you have said it is not a regular payment')

    expect(Forecast::Month.new(month: Date.current).expected)
      .to eq(before_setting - Money.from_amount(218.85))
  end

  it 'gives a frequency back to the history' do
    visit_frequencies
    select 'Yearly', from: 'How often Octopus Energy is paid'
    click_button 'Save frequencies'

    expect(page).to have_select('How often Octopus Energy is paid', selected: 'Yearly')

    select 'Work it out from the history', from: 'How often Octopus Energy is paid'
    click_button 'Save frequencies'

    expect(page).to have_select('How often Octopus Energy is paid',
                                selected: 'Work it out from the history')
    expect(PaymentSchedule.count).to be_zero
  end

  it 'shows the same payees on the forecast’s own workings page' do
    visit_frequencies
    select 'Monthly', from: 'How often NEW BROADBAND CO is paid'
    click_button 'Save frequencies'

    visit forecast_path
    within('#forecast') { click_link 'Subscriptions' }

    within('#regular_payments') do
      expect(page).to have_content('NEW BROADBAND CO')
      # Traceable to the person who asserted it, rather than reading as something the history said.
      expect(page).to have_content('Monthly (set by hand)')
    end
    within('#not_forecast') { expect(page).to have_content('ANCIENT STREAMING CO') }
  end
end
