class LloydsImportFileGenerator
  attr_reader :account, :transactions, :import_columns_definitions

  # Initialize.
  def initialize
    @account = Account.find_by_name("Lloyds Account") || FactoryBot.create(:lloyds_account)
    @transactions = []
    @import_columns_definitions = FactoryBot.create(:lloyds_import_columns_definition)
  end

  # Does the real work of generating the file.  At the end, we have a CSV export file that could have come from
  # Lloyds bank's website in the tmp folder.
  def generate(filename)
    salary
    single_transaction(6.days, :octopus_energy_imported_trx)
    repeated_transactions([ 3, 1, 3, 1, 1, 1, 3, 4, 2, 4 ], :tesco_shop)
    repeated_transactions([6, 8, 7, 10, 10], :amazon_imported_trx)
    sort
    add_balances
    write_file
  end

  private

  # Gemerate a single salary credit into the account.
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

  # Finally, we write the test output CSV file into the tmp directory.
  def write_file
    import_columns_definitions = FactoryBot.create(:lloyds_import_columns_definition)
    csv_file = CSV.open(Rails.root.join('tmp', 'lloyds_import_file.csv'), 'w', write_headers: true)
    csv_file << import_columns_definitions.csv_header
    @transactions.reverse.each { |trx| csv_file << import_columns_definitions.build_csv_data(trx) }
    csv_file.close
  end
end
