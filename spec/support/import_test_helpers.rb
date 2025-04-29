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

  # Deletes the test file for the given account
  # @param account [Account] The account whose test file should be removed
  # @return [Boolean] Result of the file removal operation
  def self.cleanup_test_file(account)
    filename_with_path = get_filename_with_path(account)
    FileUtils.rm_f(filename_with_path)
  end
end
