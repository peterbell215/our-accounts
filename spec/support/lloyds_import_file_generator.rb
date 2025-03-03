class LloydsImportFileGenerator
  attr_reader :account, :transactions, :import_columns_definitions

  def initialize
    @account = Account.find_by_name("Lloyds Account") || FactoryBot.create(:lloyds_account)
    @transactions = []
    @import_columns_definitions = FactoryBot.create(:lloyds_import_columns_definition)
  end

  # Does the real work of generating the file.  At the end, we have a CSV export file that could have come from
  # Lloyds bank's website in the tmp folder.
  def generate(filename)
    utility
    tesco_food
    sort
    write_file
  end

  def utility
    @transactions <<
      FactoryBot.build(:octopus_energy_imported_trx, account: @account, date: @account.opening_date + 6.days)
  end

  # Tesco shops happen every few days.  We have a defined array of the gaps and create a transaction accordingly.
  # @return [void]
  def tesco_food
    [ 3, 1, 3, 1, 1, 1, 3, 4, 2, 4 ].inject(@account.opening_date) do |current_day, day_gap|
      @transactions << FactoryBot.build(:tesco_shop, date: current_day)
      current_day + day_gap.days
    end
  end

  def add_balances
    @transactions.inject(@account.opening_balance) { |balance, trx| trx.balance = balance + trx.amount }
  end

  # Transactions are sorted by date descending in the Lloyds CSV export file.
  def sort
    @transactions.sort { |trx1, trx2| trx1.date <=> trx2.date }
  end


  def write_file
    import_columns_definitions = FactoryBot.create(:lloyds_import_columns_definition)
    csv_file = CSV.open(Rails.root.join('tmp', 'lloyds_import_file.csv'), 'w', write_headers: true)
    @transactions.each { |trx| csv_file << import_columns_definitions.build_csv_data(trx) }
    csv_file.close
  end
end
