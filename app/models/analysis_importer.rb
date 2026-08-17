require "csv"

# Form A of the import: bootstraps categorisation from a previously hand-analysed statement.
#
# The analysis spreadsheet is an ordinary statement export with a Category column filled in by hand.  It
# is not loaded as transaction history.  It is labelled training data, used to derive the Category list
# and the ImportMatcher rules that the raw statement import (FileImporter, form B) then relies on.
#
# Matching is on the transaction description alone, left as a literal rather than a regex, and trx_type
# is left unset so that a rule is not tied to one transaction type.
#
# Note the asymmetry: categories are global, so they are taken from the whole file, but rules belong to
# an account and are built only from that account's rows.
class AnalysisImporter
  include AnalysisFile

  # Account#name is validated as 3 to 50 characters, and descriptions run from 2 to 76.
  NAME_RANGE = (3..50).freeze

  attr_reader :file, :account, :categories_created, :matchers_created, :ambiguous,
              :counterparties_unnamed, :other_account_rows

  # @param [Pathname, String] file the analysis CSV
  # @param [Account] account the account the derived rules apply to
  def initialize(file, account)
    @file = file
    @account = account
    @categories_created = 0
    @matchers_created = 0
    @ambiguous = []
    @counterparties_unnamed = []
    @other_account_rows = 0
  end

  # @return [AnalysisImporter] self, so the caller can read the counts back
  def import
    csv = CSV.read(file, headers: true)
    raise ImportError, "#{file} has no #{CATEGORY_COLUMN} column" unless csv.headers.include?(CATEGORY_COLUMN)

    ActiveRecord::Base.transaction do
      @categories_created = Category.import_from_csv(file)
      build_matchers(labelled_rows(csv))
    end

    self
  end

  private

  # Rows carrying both a description and a category, with Excel's leading quotes removed.  The
  # description keeps its surrounding whitespace, because FileImporter does not strip it either and the
  # two have to compare equal.
  # @param [CSV::Table] csv
  # @return [Array<Array(String, String)>]
  def labelled_rows(csv)
    identifiers = account_identifiers(csv)

    csv.filter_map do |row|
      unless belongs_to_account?(row, identifiers)
        @other_account_rows += 1
        next
      end

      description = strip_leading_quote(row[DESCRIPTION_COLUMN])
      category = strip_leading_quote(row[CATEGORY_COLUMN])

      [ description, category ] if description.present? && category.present?
    end
  end

  # One rule per description.  A description that was filed under several categories takes the most
  # frequent, since the analysis was done by hand and the occasional slip is expected; an outright tie
  # is recorded and skipped rather than guessed at.
  # @param [Array<Array(String, String)>] rows
  # @return [void]
  def build_matchers(rows)
    rows.group_by(&:first).each do |description, group|
      ranked = group.map(&:last).tally.sort_by { |_, count| -count }

      if ranked.size > 1 && ranked[0][1] == ranked[1][1]
        @ambiguous << [ description, ranked.to_h ]
        next
      end

      build_matcher(description, ranked.first.first, trading_account_for(description))
    end
  end

  # @return [void]
  def build_matcher(description, category_name, other_party)
    matcher = ImportMatcher.find_or_initialize_by(account: account, description: description)
    was_new = matcher.new_record?

    matcher.category = Category.find_or_create_by!(name: category_name)
    matcher.other_party = other_party
    matcher.description_is_regex = false
    matcher.save!

    @matchers_created += 1 if was_new
  end

  # The statement only tells us the description, so that is what the counterparty is named after, trimmed
  # to fit Account's name validation.  Those names are therefore raw statement text ("TESCO STORES 2889"),
  # worth consolidating by hand on the counterparties screen.
  #
  # A description too short to make a valid name still gets its rule — the rule's job is the category, and
  # ImportMatcher#other_party is optional — but is recorded so the caller can report it.
  # @param [String] description
  # @return [TradingAccount, nil]
  def trading_account_for(description)
    name = description.squish[0, NAME_RANGE.max]

    if name.length < NAME_RANGE.min
      @counterparties_unnamed << description
      return nil
    end

    TradingAccount.find_or_create_by!(name: name)
  end
end
