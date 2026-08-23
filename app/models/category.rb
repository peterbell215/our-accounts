# Class to represent a category of transactions that we want to group such as 'Utilities' or 'Regular Savings'.
# Categories are preloaded as part of the import process to the DB, but can then be managed and augmented.
class Category < ApplicationRecord
  # How many complete months the average looks back over, where a category does not say otherwise.
  DEFAULT_FORECAST_MONTHS = 6

  # What each forecast method is called on screen.  These are the words the reader chooses between on the
  # category form and reads back on the forecast, so they belong with the values rather than in a view.
  FORECAST_METHOD_LABELS = {
    "monthly_average" => "An average of recent months",
    "regular_payments" => "Its regular payments, one at a time",
    "manual" => "A figure I enter myself",
    "excluded" => "Not forecast"
  }.freeze

  # A category a rule still assigns cannot go: import_matchers.category_id has a foreign key and the rule has
  # no meaning without it, so the delete is refused with an error the screen can show rather than raising
  # ActiveRecord::InvalidForeignKey out of the controller.  Transactions are only labelled with a category,
  # so they keep everything else and simply stop naming one — and being nullified explicitly, they no longer
  # leave transactions.category_id pointing at a row that has gone, which no foreign key would have caught.
  has_many :transactions, dependent: :nullify
  has_many :import_matchers, dependent: :restrict_with_error

  # Unlike either of those, this one is destroyed with the category.  A figure entered by hand is a
  # prediction *of* this category's spend and means nothing without it, so there is nothing to preserve
  # and nothing to refuse the delete over.
  has_many :manual_forecasts, dependent: :destroy

  # And so is a frequency set by hand for one of this category's payees: it is a ruling about how this
  # category's spending behaves, and means nothing once the category has gone.
  has_many :payment_schedules, dependent: :destroy

  # How this category's spend is predicted.  Categories differ in kind: some are steady in aggregate and
  # unpredictable transaction by transaction, so an average of recent months is as good a guess as any;
  # some are a handful of direct debits, better predicted one at a time; some are too lumpy to infer
  # anything from and are left to the reader; and some — paying off a card, moving money between our own
  # accounts — are not spending at all, and counting them would count the same money twice.
  #
  # `prefix:` keeps the predicates meaningful: `category.forecast_manual?` rather than a bare `manual?`.
  # `scopes: false` because nothing needs one — the forecast loads every category at once — and because a
  # generated class scope is how the obvious name for the first value, `average`, would have collided with
  # ActiveRecord::Calculations#average.  `validate: true` makes a hand-crafted request a 422 rather than an
  # ArgumentError raised out of the setter.
  enum :forecast_method,
       { monthly_average: "monthly_average", regular_payments: "regular_payments",
         manual: "manual", excluded: "excluded" },
       prefix: :forecast, scopes: false, default: :monthly_average, validate: true

  validates :name, presence: true, uniqueness: true, length: { minimum: 3, maximum: 50 }
  validates :forecast_months,
            numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 24 },
            allow_nil: true

  # How many complete months this category's average looks back over.
  #
  # @return [Integer]
  def forecast_window = forecast_months || DEFAULT_FORECAST_MONTHS

  # What this category's forecast method is called on screen.
  #
  # @return [String]
  def forecast_method_label = FORECAST_METHOD_LABELS.fetch(forecast_method)

  # Every counterparty named by a transaction filed under this category, with how many transactions name
  # it and what they came to.  Biggest spend first: amounts are stored negative, so ascending by total
  # does that — the same reasoning as CounterpartiesController#sort_key.  Name breaks the tie, so the many
  # counterparties a category has exactly one transaction with still come out in a readable order.
  #
  # Transactions naming nobody are left out rather than gathered into a row of their own: a one-off
  # purchase, or a description too cryptic to identify, is expected to have no counterparty.
  #
  # One grouped query and one load, rather than a count and a sum per row: the analysis import left a few
  # hundred counterparties, and a busy category names a good number of them.  Ordered in Ruby for the same
  # reason CounterpartiesController#index is — the count and the total are grouped values rather than
  # columns to ORDER BY.
  #
  # @return [Array<Array(Counterparty, Integer, Money)>]
  def counterparty_spend
    rows = transactions.where.not(counterparty_id: nil)
                       .group(:counterparty_id)
                       .pluck(:counterparty_id, Arel.sql("COUNT(*)"), Arel.sql("SUM(amount_pence)"))

    counterparties = Counterparty.where(id: rows.map(&:first)).index_by(&:id)

    rows.map { |id, count, pence| [ counterparties[id], count, Money.new(pence) ] }
        .sort_by { |counterparty, _count, total| [ total, counterparty.name.downcase ] }
  end

  # Imports category names from a CSV holding a "Category" column, such as the outgoings analysis
  # spreadsheet.  Files without that column, for example a raw bank statement, are ignored.
  #
  # Existing categories are left untouched rather than being recreated, so this is safe to run
  # repeatedly.  That matters because transactions and import matchers reference categories by id.
  #
  # @param [Pathname, String] file
  # @return [Integer] the number of categories created
  def self.import_from_csv(file)
    csv = begin
      CSV.read(file, headers: true)
    rescue CSV::MalformedCSVError
      return 0
    end

    return 0 unless csv.headers.include?("Category")

    csv.count do |row|
      name = row["Category"]
      # Excel de-marks a string with a leading single quote, which we strip.
      name = name[1..] if name&.start_with?("'")
      next false if name.blank?

      find_or_create_by!(name: name).previously_new_record?
    end
  end
end
