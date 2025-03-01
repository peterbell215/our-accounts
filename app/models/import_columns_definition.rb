# This describes how a row in an import is mapped into the ImportedTransaction model.  The actual work is done by
# the FileImporter class in collaboration with ImportedTransactionFactory.
class ImportColumnsDefinition < ApplicationRecord
  belongs_to :account

  validates :account_id, presence: true

  def build_csv_data(trx)
    data = Array.new
    extract_data(data, :date_column) { trx.date.strftime(self.date_format) }
    extract_data(data, :trx_type_column, trx.trx_type)
    extract_data(data, :sortcode_column) { trx.account.sortcode }
    extract_data(data, :account_number_column) { trx.account.account_number }
    extract_data(data, :credit_column) { trx.amount > 0 ? trx.amount.to_f : nil }
    extract_data(data, :debit_column) { trx.amount < 0 && trx.amount.to_f * -1.0 }
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
  # @param [Array] data the array being populated
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
