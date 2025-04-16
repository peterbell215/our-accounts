# This describes how a row in an import is mapped into the ImportedTransaction model.  The actual work is done by
# the FileImporter class in collaboration with ImportedTransactionFactory.
class ImportColumnsDefinition < ApplicationRecord
  belongs_to :account

  validates :account_id, presence: true

  # Generates an array of column names or column numbers.
  # @return [Array]
  def self.csv_header
    @csv_header ||= ImportColumnsDefinition.attribute_names.dup.keep_if { |a| a =~ /_column\z/ }.freeze
  end

  # Because we use the same attribute to store the column whether the column is referenced by a column header or
  # an integer index, we need to cast the column name to an integer if no header row is used.  This creates a set
  # of access methods that do that casting if required.
  csv_header.each do |attribute_name|
    define_method(attribute_name) do
      value = super()
      value = value.to_i if !self.header && __method__ =~ /_column$/ && value
      value
    end
  end


  def self.analyze_csv(file)
    # Read only the first few rows to get headers/structure without loading the whole file
    # Using headers: true attempts to read the first row as headers
    csv_options = { headers: true, return_headers: false } # Start assuming headers exist
    headers = nil
    first_data_row = nil

    # Try reading with headers
    begin
      csv = CSV.new(file.tempfile, **csv_options)
      headers = csv.first&.headers # Read just the header row
      file.tempfile.rewind # Rewind after reading headers
      csv = CSV.new(file.tempfile, **csv_options) # Re-initialize CSV object
      first_data_row = csv.first&.fields # Read the first data row
    rescue CSV::MalformedCSVError => e
      # If headers: true fails (e.g., inconsistent columns), try without it
      Rails.logger.warn("CSV parsing with headers failed: #{e.message}. Trying without headers.")
      headers = nil # Reset headers
      csv_options = { headers: false }
      file.tempfile.rewind
      csv = CSV.new(file.tempfile, **csv_options)
      first_data_row = csv.first # Read the first row as data
    end

    file.tempfile.rewind # Ensure file is rewound for potential re-reads if needed

    # Prepare columns data (index and value from first data row)
    columns_data = (first_data_row || []).map.with_index do |value, index|
      { index: index, value: value&.strip } # Strip whitespace
    end

    [headers, columns_data]
  end

  # Builds a CSV::Row object from the Transaction object.
  # @param [Transaction] trx
  # @return [CSV::Row]
  def build_csv_data(trx)
    data = CSV::Row.new(self.header ? csv_header : Array.new(csv_header.size), Array.new(csv_header.size))
    extract_data(data, :date_column) { trx.date.strftime(self.date_format) }
    extract_data(data, :trx_type_column, trx.trx_type)
    extract_data(data, :sortcode_column) { trx.account.sortcode }
    extract_data(data, :account_number_column) { trx.account.account_number }
    extract_data(data, :credit_column) { trx.amount > 0 ? trx.amount.to_f : nil }
    extract_data(data, :debit_column) { trx.amount < 0 ? trx.amount.to_f * -1.0 : nil }
    extract_data(data, :balance_column) { trx.balance.to_f }
    extract_data(data, :other_party_column, trx.description)

    data
  end

  # Does the heavy lifting of extracting a specific datum from the trx and writing it into the appropriate row.
  # It has two forms of invocation:
  # - ```extract_data(data, :trx_type_column, trx.trx_type)``` can be used if the datum is a simple type (eg String, Number)
  # - ```extract_data(data, :sortcode_column) { trx.account.sortcode }``` can be used if a more complex conversion of the
  #   type is required
  #
  # @param [CSV::Row] data the array being populated
  # @param [Symbol] column_index_field should match the names in the ImportColumnDefinition field holding the indexes
  # @param [Object] field_value
  # @param [Block] block
  # @return [void]
  def extract_data(data, column_index_field, field_value = nil)
    column_index = self[column_index_field]

    if column_index
      field_value ||= yield
      data[column_index] = field_value.is_a?(String) && field_value =~ /^[0-9]+[+-]/  ? "'" + field_value : field_value
    end
  end
end
