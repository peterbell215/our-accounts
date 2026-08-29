require 'csv'

module ImportTestHelpers
  # @param account [Account] The account to generate a filename for
  # @return [String] A parameterized string based on the account name
  def self.get_filename_for_account(account)
    "#{account.name.parameterize}.csv"
  end

  # @param account [Account] The account to generate a path for
  # @return [Pathname] Full path including filename for the account
  def self.get_filename_with_path(account)
    filename = get_filename_for_account(account)
    Rails.root.join('tmp', filename)
  end

  # Generates a test file with account transaction data
  # @param account [Account] The account to generate transactions for
  # @param import_columns_definition_factory [Symbol, nil] Optional factory for column definitions
  # @return [Pathname] The path to the generated file
  def self.generate_test_file(account, import_columns_definition_factory: nil)
    filename_with_path = get_filename_with_path(account)

    AccountTrxDataGenerator.new(
      account: account,
      import_columns_definition_factory: import_columns_definition_factory
    ).generate(output: filename_with_path)

    filename_with_path
  end

  # Writes an explicit list of transactions to the account's test file, in the layout its
  # ImportColumnsDefinition describes.
  #
  # AccountTrxDataGenerator builds a realistic seventeen-transaction history, which is the right fixture for
  # "does a whole statement load".  It is the wrong one for the skip logic, where what matters is a file of
  # two rows that are deliberately identical, or one row whose balance has been tampered with.  This goes
  # through the same #build_csv_data round-trip, so the file is in the layout the definition describes by
  # construction rather than by a hand-written CSV that could drift from it.
  #
  # @param account [Account] the account whose test file is written
  # @param transactions [Array<Transaction>] in the order they should appear in the file, newest first for a
  #   reversed layout
  # @param import_columns_definition [ImportColumnsDefinition, nil] defaults to the account's own
  # @return [Pathname] the path to the written file
  def self.write_statement(account, transactions, import_columns_definition: nil)
    definition = import_columns_definition || ImportColumnsDefinition.find_by(account_id: account.id)
    filename_with_path = get_filename_with_path(account)

    CSV.open(filename_with_path, 'w', write_headers: definition.header) do |csv_file|
      csv_file << definition.csv_header if definition.header
      transactions.each { |trx| csv_file << definition.build_csv_data(trx) }
    end

    filename_with_path
  end

  # Deletes the test file for the given account
  # @param account [Account] The account whose test file should be removed
  # @return [Boolean] Result of the file removal operation
  def self.cleanup_test_file(account)
    filename_with_path = get_filename_with_path(account)
    FileUtils.rm_f(filename_with_path)
  end
end
