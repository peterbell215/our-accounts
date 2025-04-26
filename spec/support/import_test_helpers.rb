module ImportTestHelpers
  FILENAME = "lloyds_import_file.csv"
  FILENAME_WITH_PATH = Rails.root.join('tmp', FILENAME)

  def self.generate_test_file(account)
    AccountTrxDataGenerator.new(account: account).generate(output: FILENAME_WITH_PATH)
    FILENAME_WITH_PATH
  end

  def self.cleanup_test_file
    FileUtils.rm_f(FILENAME_WITH_PATH)
  end
end
