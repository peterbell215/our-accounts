module ImportTestHelpers
  LLOYDS_FILENAME = "lloyds_import_file.csv"
  BARCLAYCARD_FILENAME = "barclaycard_import_file.csv"

  def self.get_filename_for_account(account)
    case account.name
    when /Barclaycard/i
      BARCLAYCARD_FILENAME
    else
      LLOYDS_FILENAME
    end
  end

  def self.get_filename_with_path(account)
    filename = get_filename_for_account(account)
    Rails.root.join('tmp', filename)
  end

  def self.generate_test_file(account, import_columns_definition_factory: nil)
    filename_with_path = get_filename_with_path(account)

    AccountTrxDataGenerator.new(
      account: account,
      import_columns_definition_factory: import_columns_definition_factory
    ).generate(output: filename_with_path)

    filename_with_path
  end

  def self.cleanup_test_file(account)
    filename_with_path = get_filename_with_path(account)
    FileUtils.rm_f(filename_with_path)
  end
end
