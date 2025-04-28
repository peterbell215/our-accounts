# This describes how a row in an import is mapped into the ImportedTransaction model.  The actual work is done by
# the FileImporter class in collaboration with ImportedTransactionFactory.
class ImportColumnsDefinition < ApplicationRecord
  belongs_to :account

  validates :account_id, presence: true
  validates :date_format, presence: true
  validates :date_column, presence: true
  validates :other_party_column, presence: true

  validate :validate_credit_debit_or_amount_column
  validate :validate_unique_csv_mappings

  CSV_HEADERS = ImportColumnsDefinition.attribute_names.dup.keep_if { |a| a =~ /_column\z/ }.freeze

  # Generates an array of column names or column numbers.
  # @return [Array]
  def csv_header
    @csv_header ||= CSV_HEADERS.map { |column| self[column] }.compact
  end

  # Because we use the same attribute to store the column whether the column is referenced by a column header or
  # an integer index, we need to cast the column name to an integer if no header row is used.  This creates a set
  # of access methods that do that casting if required.
  CSV_HEADERS.each do |attribute_name|
    define_method(attribute_name) do
      value = super()
      value = value.to_i if !self.header && __method__ =~ /_column$/ && value
      value
    end
  end

  # This Ruby code defines a class method `analyze_csv` within the
  # `ImportColumnsDefinition` class. Its purpose is to inspect the beginning of
  # a provided CSV file to determine its structure, specifically identifying
  # potential headers and capturing the content of the first data row, without
  # loading the entire file into memory.
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

    [ headers, columns_data ]
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
  # @return [void]
  def extract_data(data, column_index_field, field_value = nil)
    column_index = self[column_index_field]

    return if column_index.nil?
    column_index = column_index.to_i unless self.header?

    field_value ||= yield
    data[column_index] = field_value.is_a?(String) && field_value =~ /^[0-9]+[+-]/  ? "'" + field_value : field_value
  end

  private

  # Custom validation to ensure either credit/debit columns or amount column are used to capture the transaction
  # value.  If so, error added to model.
  # @return void
  def validate_credit_debit_or_amount_column
    using_credit_debit = (!credit_column.blank? && !debit_column.blank?) && amount_column.blank?
    using_amount = (credit_column.blank? && debit_column.blank?) && !amount_column.blank?

    if using_credit_debit == using_amount
      errors.add(:base, "You must define either both credit_column and debit_column, or amount_column.")
    end
  end

  # Custom validation to ensure no duplicate mappings in CSV columns
  def validate_unique_csv_mappings
    mapped_columns = mapped_columns = self.attributes.select { |a, v| a.in?(CSV_HEADERS) && v.present? }.values
    duplicates = mapped_columns.select { |value| mapped_columns.count(value) > 1 }.uniq

    if duplicates.any?
      errors.add(:base, "The same field in the CSV file cannot be mapped to multiple columns: #{duplicates.join(', ')}")
    end
  end
end
