require "csv"

# Builds an account and its history from the statement files that came with it.
#
# This is the whole pipeline in order: the account itself, the definition describing how its statements
# are laid out, the categorisation rules derived from a hand-analysed spreadsheet (form A), the
# statement import (form B), and finally the hand-assigned categories applied over the top.
#
# Every step is idempotent or skipped once done, so seeding can be re-run against an existing database.
#
# The account name and the two filenames identify a real account, so they come from the encrypted
# credentials rather than from source.  See db/seeds.rb.
class AccountSeeder
  # Describes a Lloyds current account export.  A second institution would need its own definition,
  # which is what /import_columns_definitions/new is for.
  LLOYDS_LAYOUT = {
    header: true, reversed: true, credit_sign: 1,
    date_column: "Transaction Date", date_format: "%d/%m/%Y",
    trx_type_column: "Transaction Type",
    sortcode_column: "Sort Code", account_number_column: "Account Number",
    other_party_column: "Transaction Description",
    amount_column: nil, debit_column: "Debit Amount", credit_column: "Credit Amount",
    balance_column: "Balance"
  }.freeze

  attr_reader :account_name, :account, :rules_created, :transactions_imported, :labels_applied,
              :labels_corrected, :import_skipped

  # @return [AccountSeeder, nil] nil when the credentials carry no seed_data
  def self.from_credentials(directory: Rails.root.join("db"))
    config = Rails.application.credentials.seed_data
    return nil if config.blank?

    new(account_name: config.account_name, raw_statement: config.raw_statement,
        analysis: config.analysis, directory: directory)
  end

  def initialize(account_name:, raw_statement:, analysis:, directory: Rails.root.join("db"))
    @account_name = account_name
    @raw_statement = raw_statement
    @analysis = analysis
    @directory = Pathname(directory)
    @import_skipped = false
  end

  # @return [Boolean] whether the credentials name all three things
  def configured?
    [ account_name, @raw_statement, @analysis ].all?(&:present?)
  end

  # @return [Array<Pathname>] the statement files that are named but not present
  def missing_sources
    [ raw_path, analysis_path ].reject(&:exist?)
  end

  # @return [AccountSeeder] self, so the caller can read the counts back
  def seed
    @account = build_account
    write_columns_definition

    @rules_created = AnalysisImporter.new(analysis_path, account).import.matchers_created
    import_transactions

    categoriser = AnalysisCategoriser.new(analysis_path, account).apply
    @labels_applied = categoriser.assigned
    @labels_corrected = categoriser.corrected.count

    self
  end

  # @return [Pathname]
  def raw_path = @directory.join(@raw_statement.to_s)

  # @return [Pathname]
  def analysis_path = @directory.join(@analysis.to_s)

  private

  # @return [Account]
  def build_account
    existing = Account.find_by(name: account_name)
    return existing if existing

    opening_date, opening_balance, sortcode, account_number = opening_position

    BankAccount.create!(name: account_name, sortcode: sortcode, account_number: account_number,
                        opening_date: opening_date, opening_balance: opening_balance)
  end

  # The raw download is in reverse date order, so the oldest transaction is the *last* row.  Deriving the
  # opening balance from it rather than hardcoding a figure keeps the account consistent with whatever
  # statement is actually present, and Transaction#sequence rejects it immediately if it is wrong.
  # @return [Array(Date, Money, String, String)]
  def opening_position
    rows = CSV.read(raw_path, headers: true)
    oldest = rows[rows.count - 1]

    amount = Money.from_amount(oldest["Credit Amount"].to_d - oldest["Debit Amount"].to_d)
    balance_after = Money.from_amount(oldest["Balance"].to_d)
    date = Date.strptime(oldest["Transaction Date"].strip, LLOYDS_LAYOUT[:date_format])

    [ date - 1, balance_after - amount,
      strip_leading_quote(oldest["Sort Code"]), strip_leading_quote(oldest["Account Number"]) ]
  end

  # @return [void]
  def write_columns_definition
    definition = ImportColumnsDefinition.find_or_initialize_by(account: account)
    definition.assign_attributes(LLOYDS_LAYOUT)
    definition.save! if definition.new_record? || definition.changed?
  end

  # FileImporter is not idempotent: a second run would double the rows up and Transaction#sequence would
  # reject the balances, so only import into an account that has none.
  # @return [void]
  def import_transactions
    if account.transactions.any?
      @import_skipped = true
      @transactions_imported = 0
      return
    end

    FileImporter.new(raw_path, account).import
    @transactions_imported = account.transactions.count
  end

  # @param [String, nil] value
  # @return [String, nil]
  def strip_leading_quote(value)
    value&.start_with?("'") ? value[1..] : value
  end
end
