require 'csv' # Ensure CSV is required

class AccountTrxDataGenerator
  attr_reader :account, :transactions, :import_columns_definitions

  # Initialize.
  # @param [Account] account The account object to associate transactions with.
  def initialize(account:)
    @account = account
    @transactions = []
    @import_columns_definitions = FactoryBot.build(:lloyds_import_columns_definition)
  end

  # Does the data generation part. Populates transactions, sorts, and adds balances.
  # Does NOT write the file.
  def generate(output: :db)
    # Clear transactions if generate is called multiple times on the same instance
    salary
    single_transaction(6.days, :octopus_energy_imported_trx)
    repeated_transactions([ 3, 1, 3, 1, 1, 1, 3, 4, 2, 4 ], :tesco_shop)
    repeated_transactions([6, 8, 7, 10, 10], :amazon_imported_trx)
    sort
    add_balances

    if output == :db
      write_to_db
    else
      write_file(output)
    end
  end

  # Writes the generated transactions to a CSV file in the tmp directory.
  # This is now a public method.
  # @param [String] filename_with_path The base name for the output CSV file (e.g., 'lloyds_import_file.csv')
  # @return [CSVFile]
  def write_file(filename_with_path)
    CSV.open(filename_with_path, 'w', write_headers: true) do |csv_file|
      csv_file << import_columns_definitions.csv_header
      # Write transactions (reversed, as before)
      @transactions.reverse.each { |trx| csv_file << import_columns_definitions.build_csv_data(trx) }
    end
  end

  private

  # Saves the generated transactions to the database.
  # Associates each transaction with the generator's account before saving.
  # Assumes the transaction objects built by factories are valid for saving.
  # @return [Integer] The number of transactions successfully saved.
  def write_to_db
    # Use transaction block for atomicity if desired (optional but good practice)
    # ActiveRecord::Base.transaction do
    transactions.each do |trx|
      # Ensure the transaction is linked to the correct account
      # This assumes the Transaction model has an `account` association
      trx.account = account

      trx.save!
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "LloydsImportFileGenerator: Failed to save transaction: #{e.message}. Record: #{trx.attributes.inspect}"
      # Re-raise the error to halt execution and fail the test/process
      raise e
    end
    # end # End of optional transaction block

    Rails.logger.info "LloydsImportFileGenerator: Successfully saved #{transactions.count} transactions to the database for account '#{account.name}'."
  end

  # Generate a single salary credit into the account.
  def salary
    @transactions << FactoryBot.build(:salary_transaction, date: @account.opening_date.end_of_month)
  end

  # Create a single debit transaction that occurs once in the month.
  # @param [Integer] days_after_opening
  # @param [Symbol] factory
  # @return [void]
  def single_transaction(days_after_opening, factory)
    @transactions << FactoryBot.build(factory, date: @account.opening_date + days_after_opening)
  end

  # Regular debit shop happening every few days.  We have a defined array of the gaps and create a transaction accordingly.
  # @return [void]
  # @param [Array<Integer>] gaps
  # @param [Symbol] factory
  def repeated_transactions(gaps, factory)
    gaps.inject(@account.opening_date) do |current_day, day_gap|
      @transactions << FactoryBot.build(factory, date: current_day)
      current_day + day_gap.days
    end
  end

  # Since transactions are created by factory, they may be out of sequence.  Transactions are sorted by date.
  # @return [void]
  def sort
    @transactions.sort! { |trx1, trx2| trx1.date <=> trx2.date }
  end

  # Having created the individual transactions and sorted them, we need to add the balances.
  def add_balances
    @transactions.inject(@account.opening_balance) { |balance, trx| trx.balance = balance + trx.amount }
  end
end
