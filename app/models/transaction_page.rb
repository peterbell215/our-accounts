# A window onto one account's transactions, newest first.
#
# An account accumulates thousands of transactions, so the account page shows a page at a time and loads
# more as the reader scrolls.  Two ideas do the work:
#
# - The **anchor** is a date.  The window covers everything on or before it, so moving the anchor moves
#   the whole list — which is what the day/week/month buttons do.  It is clamped to the account's own
#   range, so those buttons can never strand the reader on an empty list.
# - The **cursor** identifies the last row already shown.  Paging is keyset rather than offset, so a
#   transaction added while someone is part-way down the list neither repeats a row nor hides one.
class TransactionPage
  SIZE = 50

  STEPS = { day: 1.day, week: 1.week, month: 1.month }.freeze

  attr_reader :account, :anchor, :transactions

  # @param [Account] account
  # @param [Date, String, nil] anchor the newest date to show; defaults to the account's newest
  # @param [Hash, nil] cursor :date, :day_index and :id of the last row already shown
  # @param [Integer] size rows per page
  def initialize(account:, anchor: nil, cursor: nil, size: SIZE)
    @account = account
    @size = size
    @anchor = clamp(coerce_date(anchor)) || latest_date
    @transactions, @more = load(cursor)
  end

  # @return [Boolean] whether older transactions remain beyond this page
  def more? = @more

  # @return [Boolean]
  def any? = transactions.any?

  # Identifies the last row on this page, for the next page to resume from.
  # @return [Hash, nil]
  def next_cursor
    last = transactions.last
    return nil if last.nil?

    { date: last.date, day_index: last.day_index || 0, id: last.id }
  end

  # @param [Symbol] unit :day, :week or :month
  # @return [Date, nil]
  def back(unit) = anchor && clamp(anchor - step(unit))

  # @param [Symbol] unit :day, :week or :month
  # @return [Date, nil]
  def forward(unit) = anchor && clamp(anchor + step(unit))

  # @return [Boolean] whether the window already reaches the account's oldest transaction
  def at_earliest? = anchor.nil? || earliest_date.nil? || anchor <= earliest_date

  # @return [Boolean] whether the window already reaches the account's newest transaction
  def at_latest? = anchor.nil? || latest_date.nil? || anchor >= latest_date

  # @return [Date, nil]
  def latest_date = @latest_date ||= account.transactions.maximum(:date)

  # @return [Date, nil]
  def earliest_date = @earliest_date ||= account.transactions.minimum(:date)

  private

  # Fetches one row more than asked for, which is how we know whether to offer another page.
  # @return [Array(Array<Transaction>, Boolean)]
  def load(cursor)
    return [ [], false ] if anchor.nil?

    scope = account.transactions.on_or_before(anchor).newest_first
    scope = scope.older_than(cursor[:date], cursor[:day_index], cursor[:id]) if cursor.present?

    rows = scope.limit(@size + 1).to_a
    [ rows.first(@size), rows.size > @size ]
  end

  # @return [Date, nil]
  def clamp(date)
    return nil if date.nil? || latest_date.nil?

    date.clamp(earliest_date, latest_date)
  end

  # @return [ActiveSupport::Duration]
  def step(unit)
    STEPS.fetch(unit.to_sym) { raise ArgumentError, "unknown step #{unit.inspect}" }
  end

  # @return [Date, nil]
  def coerce_date(value)
    return value if value.is_a?(Date)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue Date::Error
    nil
  end
end
