# Applies the hand-assigned categories from an analysis spreadsheet to transactions already imported.
#
# AnalysisImporter turns the same spreadsheet into ImportMatcher rules, which generalise a category over
# every transaction sharing a description.  That is a good approximation, but it flattens the cases where
# the same payee genuinely belongs to different categories on different occasions, and it refuses to
# guess where the analysis was evenly split.  This puts the original per-transaction judgements back.
#
# Rows are matched on date and running balance.  That pair is unique — a running balance cannot repeat
# within a day — and it is reliable by construction, because Transaction#sequence has already verified
# each imported balance against the same statement.  Matching on description and amount would not do:
# there are descriptions that repeat with the same amount on the same day.
class AnalysisCategoriser
  include AnalysisFile

  attr_reader :file, :account, :assigned, :corrected, :unchanged, :not_found

  # @param [Pathname, String] file the marked-up analysis CSV
  # @param [Account] account the account whose transactions are being labelled
  def initialize(file, account)
    @file = file
    @account = account
    @assigned = 0
    @corrected = []
    @unchanged = 0
    @not_found = []
  end

  # @return [AnalysisCategoriser] self, so the caller can read the counts back
  def apply
    csv = CSV.read(file, headers: true)
    [ CATEGORY_COLUMN, DATE_COLUMN, BALANCE_COLUMN ].each do |column|
      raise ImportError, "#{file} has no #{column} column" unless csv.headers.include?(column)
    end

    identifiers = account_identifiers(csv)

    ActiveRecord::Base.transaction do
      csv.each { |row| apply_row(row) if belongs_to_account?(row, identifiers) }
    end

    self
  end

  private

  # @param [CSV::Row] row
  # @return [void]
  def apply_row(row)
    category_name = strip_leading_quote(row[CATEGORY_COLUMN])
    date = parse_date(row[DATE_COLUMN])
    balance = parse_balance(row[BALANCE_COLUMN])
    return if category_name.blank? || date.nil? || balance.nil?

    transaction = account.transactions.find_by(date: date, balance_pence: balance.fractional)

    if transaction.nil?
      @not_found << [ date, strip_leading_quote(row[DESCRIPTION_COLUMN]).to_s.squish, balance.format ]
      return
    end

    assign(transaction, Category.find_or_create_by!(name: category_name))
  end

  # The hand analysis is authoritative, so it overrides whatever a rule concluded, but a category that
  # was already right is left alone rather than counted as a change.
  # @return [void]
  def assign(transaction, category)
    if transaction.category_id == category.id
      @unchanged += 1
      return
    end

    @corrected << [ transaction.description.to_s.squish, transaction.category&.name, category.name ] if transaction.category
    transaction.update!(category: category)
    @assigned += 1
  end

  # @param [String, nil] value
  # @return [Money, nil]
  def parse_balance(value)
    value = value.to_s.strip
    return nil if value.empty?

    Money.from_amount(value.to_d)
  rescue ArgumentError
    nil
  end
end
