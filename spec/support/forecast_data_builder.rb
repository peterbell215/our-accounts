# A household's spending history, shaped so that each forecast method has something real to work on.
#
# `AccountTrxDataGenerator` cannot serve the forecast: it assigns no categories at all, its transactions
# are pinned to the account's opening date rather than to the month under test, and it is shared with the
# `data:create_sample_data` rake task — so bending it to this would risk the import specs for no gain.
#
# Everything here is placed relative to a `today` the caller supplies, so a spec says what situation it is
# testing rather than freezing the clock.
#
# Balances are deliberately left unset. `balance_pence` is nullable, the forecast never reads it, and
# skipping the running total keeps `Transaction#sequence` — and its ImportError on a mismatch — out of a
# fixture that is not about importing.
class ForecastDataBuilder
  attr_reader :account, :food, :subscriptions, :holidays, :transfers, :energy, :water

  # @param [Date] today
  def initialize(today: Date.current)
    @today = today
    @month = today.beginning_of_month
  end

  # @return [ForecastDataBuilder] self, so a spec can reach the records it made
  def build
    @account = create(:lloyds_account, opening_date: months_ago(24))

    @food = create(:food_category)
    @subscriptions = create(:subscriptions_category)
    @holidays = create(:holidays_category)
    @transfers = create(:transfers_category)

    @energy = create(:counterparty, name: "Octopus Energy", account_number: "1")
    @water = create(:counterparty, name: "South Staffs Water", account_number: "2")

    food_shops
    energy_by_direct_debit
    water_quarterly
    cancelled_subscription
    card_payment
    uncategorised
    salary

    self
  end

  private
    def create(*args, **kwargs) = FactoryBot.create(*args, **kwargs)

    # `months_ago(1)` is the 15th of last month — a day that exists in every month, so nothing shifts
    # under a 30-day month or February.
    def months_ago(count, day: 15) = (@month << count).change(day: day)

    # Six months of the weekly-ish shop, at amounts that average to something a spec can state exactly:
    # 100, 200, 300, 400, 500, 600 over six months is 350 a month.
    def food_shops
      [ 100, 200, 300, 400, 500, 600 ].each_with_index do |amount, offset|
        spend(months_ago(6 - offset), "TESCO STORES 2889", amount, category: @food)
      end
    end

    # Eight months of a monthly direct debit that steps up. The most recent figure is what the forecast
    # should predict, not the average of the eight.
    def energy_by_direct_debit
      amounts = [ 200.00, 200.00, 200.00, 200.00, 210.00, 210.00, 218.85 ]

      amounts.each_with_index do |amount, offset|
        spend(months_ago(amounts.count - offset, day: 19), "OCTOPUS ENERGY", amount,
              category: @subscriptions, counterparty: @energy, trx_type: "DD")
      end
    end

    # Quarterly, so it is due only in some months — the case a monthly cadence would get wrong.
    def water_quarterly
      [ 9, 6, 3 ].each do |offset|
        spend(months_ago(offset, day: 3), "SOUTH STAFFS WATER", 40.00,
              category: @subscriptions, counterparty: @water, trx_type: "DD")
      end
    end

    # A clean monthly cadence that stopped a year ago. Without the staleness rule this reads as due every
    # month for ever.
    def cancelled_subscription
      [ 18, 17, 16, 15, 14, 13 ].each do |offset|
        spend(months_ago(offset, day: 8), "ANCIENT STREAMING CO", 9.99, category: @subscriptions, trx_type: "DD")
      end
    end

    # Paying off the card: excluded, because the spending already happened on the card.
    def card_payment
      3.downto(0) { |offset| spend(months_ago(offset, day: 28), "CARD PAYMENT", 500.00, category: @transfers) }
    end

    # No category at all, which on real data is about a third of everything.
    def uncategorised
      [ 3, 2, 1, 0 ].each { |offset| spend(months_ago(offset, day: 12), "SOMETHING UNFILED", 80.00) }
    end

    # Income, to prove it is filtered out rather than counted as negative spending.
    def salary
      FactoryBot.create(:transaction, account: @account, date: months_ago(0, day: 25),
                                      description: "EMPLOYER CURRENT", trx_type: "BGC",
                                      amount: Money.from_amount(3000.00))
    end

    def spend(date, description, amount, category: nil, counterparty: nil, trx_type: "DEB")
      FactoryBot.create(:transaction, account: @account, date: date, description: description,
                                      trx_type: trx_type, category: category, counterparty: counterparty,
                                      amount: Money.from_amount(-amount))
    end
end
