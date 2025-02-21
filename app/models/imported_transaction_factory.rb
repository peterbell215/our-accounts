require "csv"

# Factory that takes a CSV row and an ImportColumnsDefinition and generates an appropriate ImportedTransaction object.
class ImportedTransactionFactory
  # @param [CSV::Row] csv_row
  # @param [ImportColumnsDefinition] import_columns_definition
  # @return [null, ImportedTransaction]
  def self.build(csv_row, import_columns_definition)
    csv_row = strip_leading_quote(csv_row)

    imported_transaction = Transaction.new
    imported_transaction.account_id = set_account_id(csv_row, import_columns_definition)
    imported_transaction.date = Date.strptime(csv_row[import_columns_definition.date_column], import_columns_definition.date_format)
    imported_transaction.trx_type = csv_row[import_columns_definition.transaction_type_column]
    imported_transaction.description = csv_row[import_columns_definition.other_party_column]
    imported_transaction.amount = set_amount(csv_row, import_columns_definition)

    if import_columns_definition.balance_column
      imported_transaction.balance = Money.from_amount(csv_row[import_columns_definition.balance_column])
    end

    imported_transaction
  end

  private

  # For CSV files imported from Excel, there is on some fields a leading single quote to demark a string.  This
  # method strips those single quotes.
  # @param [CSV::Row] csv_row
  # @return [Array] returns the array of column values with any leading single quotes removed
  def self.strip_leading_quote(csv_row)
    csv_row.fields.map! { |s| s.is_a?(String) && s[0] == "'" && s[-1]!="'" ? s[1..] : s }
  end

  # If the import file contains the account details, check that they match the account we are importing to.
  # @param [CSV::Row] csv_row
  # @param [ImportColumnsDefinition] import_columns_definition
  # @return [Money]
  def self.set_account_id(csv_row, import_columns_definition)
    if import_columns_definition.sortcode_column
      account_details_match =
        csv_row[import_columns_definition.sortcode_column]==import_columns_definition.account.sortcode &&
        csv_row[import_columns_definition.account_number_column]==import_columns_definition.account.account_number

      raise ImportError, "Sortcode and/or account number do not match with input file" unless account_details_match
    end

    import_columns_definition.account.id
  end

  # Determine the transaction amount.
  # @param [CSV::Row] csv_row
  # @param [ImportColumnsDefinition] import_columns_definition
  # @return [Money]
  def self.set_amount(csv_row, import_columns_definition)
    if import_columns_definition.amount_column
      amount = csv_row[import_columns_definition.amount_column]
    else
      amount = csv_row[import_columns_definition.credit_column] || -csv_row[import_columns_definition.debit_column]
      amount *= import_columns_definition.credit_sign
    end
    Money.from_amount(amount)
  end
end
