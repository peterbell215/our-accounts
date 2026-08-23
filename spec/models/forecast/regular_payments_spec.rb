require 'rails_helper'

describe Forecast::RegularPayments, type: :model do
  let(:today) { Date.new(2026, 7, 10) }
  let(:month) { Date.new(2026, 7, 1) }
  let(:account) { create(:lloyds_account, opening_date: Date.new(2023, 1, 1)) }
  let(:subscriptions) { create(:subscriptions_category) }
  let(:energy) { create(:counterparty, name: "Octopus Energy", account_number: "1") }
  let(:water) { create(:counterparty, name: "South Staffs Water", account_number: "2") }

  # @param [Integer] months_ago 0 is the month being forecast
  def spend(months_ago, amount, description: "OCTOPUS ENERGY", counterparty: energy, day: 19)
    create(:transaction, account: account, category: subscriptions, counterparty: counterparty,
                         date: (month << months_ago).change(day: day), description: description,
                         trx_type: "DD", amount: Money.from_amount(-amount))
  end

  def detector
    history = Forecast::History.new(month: month, today: today, categories: [ subscriptions ])

    described_class.new(rows: history.all_rows_for(subscriptions.id), month: month)
  end

  def payment(label) = detector.payments.find { |candidate| candidate.label == label }

  describe 'recognising a payment' do
    it 'finds a monthly direct debit and expects it again' do
      6.downto(1) { |ago| spend(ago, 200.00) }

      expect(payment("Octopus Energy")).to have_attributes(cadence: 1, due: true, amount: Money.from_amount(200.00))
    end

    # The whole reason to predict a category this way rather than by its average: a direct debit steps up
    # and the new figure is what next month costs. An average of the eight would say £205.55.
    it 'predicts the most recent amount rather than an average of them' do
      [ 200.00, 200.00, 200.00, 210.00, 210.00, 218.85 ].each_with_index do |amount, index|
        spend(6 - index, amount)
      end

      expect(payment("Octopus Energy").amount).to eq(Money.from_amount(218.85))
    end

    it 'says nothing about a payee seen only once' do
      spend(1, 200.00)

      expect(detector.payments).to be_empty
    end

    it 'groups on the description where a payee has no counterparty' do
      3.downto(1) { |ago| spend(ago, 12.00, description: "ANCIENT STREAMING CO", counterparty: nil) }

      expect(payment("ANCIENT STREAMING CO")).to have_attributes(cadence: 1, due: true)
    end
  end

  describe 'cadence' do
    it 'expects a quarterly payment only in the months it falls due' do
      [ 9, 6, 3 ].each { |ago| spend(ago, 40.00, description: "SOUTH STAFFS WATER", counterparty: water, day: 3) }

      expect(payment("South Staffs Water")).to have_attributes(cadence: 3, due: true)
    end

    it 'does not expect a quarterly payment in the month after it went out' do
      [ 7, 4, 1 ].each { |ago| spend(ago, 40.00, description: "SOUTH STAFFS WATER", counterparty: water, day: 3) }

      expect(payment("South Staffs Water")).to have_attributes(cadence: 3, due: false)
      expect(detector.expected).to eq(Money.from_amount(0))
    end

    # A six-month detection window would hold at most one occurrence of this and could never recognise it,
    # which is why detection runs over all history rather than over the average's window.
    it 'finds an annual payment from two years of history' do
      [ 24, 12 ].each { |ago| spend(ago, 350.00, description: "HOME INSURANCE", counterparty: nil, day: 7) }

      expect(payment("HOME INSURANCE")).to have_attributes(cadence: 12, due: true, amount: Money.from_amount(350.00))
    end
  end

  # What replaces the detection window. Without it a clean monthly cadence that stopped years ago reads
  # as due every month for ever.
  describe 'a series that has stopped' do
    it 'drops a monthly payment last seen more than a month and a cadence ago' do
      [ 18, 17, 16, 15, 14, 13 ].each { |ago| spend(ago, 9.99, description: "ANCIENT STREAMING CO", counterparty: nil) }

      expect(detector.payments).to be_empty
      expect(detector.expected).to eq(Money.from_amount(0))
    end

    it 'keeps a monthly payment that has merely skipped a month' do
      [ 4, 3, 2 ].each { |ago| spend(ago, 20.00) }

      expect(payment("Octopus Energy")).to be_present
    end
  end

  describe 'a series too erratic to schedule' do
    it 'reports it rather than dropping it in silence' do
      [ 30, 15 ].each { |ago| spend(ago, 75.00, description: "ODD JOB", counterparty: nil) }

      expect(detector.payments.map(&:label)).not_to include("ODD JOB")
      expect(detector.irregular).to include("ODD JOB")
    end
  end

  describe '#remaining — the requirement' do
    before do
      6.downto(1) { |ago| spend(ago, 218.85) }
      [ 9, 6, 3 ].each { |ago| spend(ago, 40.00, description: "SOUTH STAFFS WATER", counterparty: water, day: 3) }
    end

    it 'expects both bills before either has gone out' do
      expect(detector.expected).to eq(Money.from_amount(258.85))
      expect(detector.remaining(Money.from_amount(0))).to eq(Money.from_amount(258.85))
    end

    it 'deducts a payment that has landed, and only that payment' do
      spend(0, 218.85)

      expect(detector.remaining(Money.from_amount(218.85))).to eq(Money.from_amount(40.00))
    end

    # The case category-level subtraction gets wrong. Expected is £258.85 and £248.85 has been spent, so
    # subtracting at the level of the category would leave £10.00 — quietly eating £30 of the water bill,
    # which has not been paid and is still going to be.
    it 'is unmoved by a landed payment coming in over its prediction' do
      spend(0, 248.85)

      expect(detector.remaining(Money.from_amount(248.85))).to eq(Money.from_amount(40.00))
    end

    it 'has nothing left to come once every payment has gone out' do
      spend(0, 218.85)
      spend(0, 40.00, description: "SOUTH STAFFS WATER", counterparty: water, day: 3)

      expect(detector.remaining(Money.from_amount(258.85))).to eq(Money.from_amount(0))
    end

    # A one-off in this category is real spending and belongs in the month's actual, but it says nothing
    # about which of the recognised payments are still to come.
    it 'is unaffected by one-off spending in the same category' do
      create(:transaction, account: account, category: subscriptions, date: month.change(day: 5),
                           description: "A ONE-OFF", amount: Money.from_amount(-500.00))

      expect(detector.remaining(Money.from_amount(500.00))).to eq(Money.from_amount(258.85))
      expect(detector.payments.map(&:label)).not_to include("A ONE-OFF")
    end
  end

  # What has gone out is a list rather than a date and a total. A monthly payment billed on the 1st and
  # again on the 29th falls twice inside one calendar month; totalling the two against the earlier of the
  # dates drew it as a single charge for twice the money, which on the page is a bill that has doubled.
  describe 'a payment that goes out more than once in a month' do
    before { 6.downto(1) { |ago| spend(ago, 7.99, day: 1) } }

    def landed_twice
      spend(0, 7.99, day: 1)
      spend(0, 7.99, day: 29)
      payment("Octopus Energy")
    end

    it 'keeps both occurrences, earliest first' do
      expect(landed_twice.landed.map(&:date)).to eq([ month.change(day: 1), month.change(day: 29) ])
    end

    it 'reports each occurrence at its own amount rather than their total' do
      expect(landed_twice.landed.map(&:amount)).to eq([ Money.from_amount(7.99), Money.from_amount(7.99) ])
    end

    it 'counts as settled, so nothing is left to come' do
      expect(landed_twice.remaining).to eq(Money.new(0))
    end

    it 'keeps the single occurrence where the payment went out once' do
      spend(0, 7.99, day: 1)

      expect(payment("Octopus Energy").landed.map(&:date)).to eq([ month.change(day: 1) ])
    end
  end

  # Forecasting a month gone by has to use only what was known at the time, or it is not a test of the
  # method at all.
  describe 'forecasting a month in the past' do
    let(:month) { Date.new(2026, 3, 1) }

    it 'ignores occurrences after the month being forecast' do
      6.downto(1) { |ago| spend(ago, 100.00) }
      spend(-1, 900.00)

      expect(payment("Octopus Energy").amount).to eq(Money.from_amount(100.00))
    end
  end

  it 'never returns a negative amount still to come' do
    6.downto(1) { |ago| spend(ago, 200.00) }
    spend(0, 5000.00)

    expect(detector.remaining(Money.from_amount(5000.00))).to eq(Money.from_amount(0))
  end
end
