require "csv"

# Shared reading of the hand-analysed statement spreadsheet.
#
# Two classes consume it: AnalysisImporter derives the ImportMatcher rules from it, and
# AnalysisCategoriser applies its per-transaction labels to transactions already imported.  Both have to
# cope with the same quirks, which come from the sheet having been maintained by hand in Excel.
module AnalysisFile
  CATEGORY_COLUMN = "Category".freeze
  DESCRIPTION_COLUMN = "Transaction Description".freeze
  DATE_COLUMN = "Transaction Date".freeze
  BALANCE_COLUMN = "Balance".freeze
  SORTCODE_COLUMN = "Sort Code".freeze
  ACCOUNT_NUMBER_COLUMN = "Account Number".freeze

  # Dates arrive in whichever format the editor left behind: most rows are dd/mm/yyyy, a run of them
  # dd-Mmm-yy.
  DATE_FORMATS = [ "%d/%m/%Y", "%d-%b-%y" ].freeze

  private

  # An analysis spreadsheet may consolidate several accounts, as the household one does: the current
  # account, two credit cards and a store card all in the same sheet.  Rows therefore have to be
  # restricted to the account in hand.
  #
  # Only columns the file actually carries, and that the account actually has a value for, are used; an
  # empty result means the file gives us nothing to discriminate on and every row is accepted.
  # @param [CSV::Table] csv
  # @return [Hash{String => String}]
  def account_identifiers(csv)
    { SORTCODE_COLUMN => account.sortcode, ACCOUNT_NUMBER_COLUMN => account.account_number }
      .select { |column, value| csv.headers.include?(column) && value.present? }
  end

  # @param [CSV::Row] row
  # @param [Hash{String => String}] identifiers
  # @return [Boolean]
  def belongs_to_account?(row, identifiers)
    identifiers.all? { |column, value| strip_leading_quote(row[column]) == value }
  end

  # @param [String, nil] value
  # @return [Date, nil]
  def parse_date(value)
    value = value.to_s.strip
    return nil if value.empty?

    DATE_FORMATS.each do |format|
      return Date.strptime(value, format)
    rescue Date::Error
      next
    end

    nil
  end

  # Excel de-marks a string with a leading single quote, which we strip.
  # @param [String, nil] value
  # @return [String, nil]
  def strip_leading_quote(value)
    value&.start_with?("'") ? value[1..] : value
  end
end
