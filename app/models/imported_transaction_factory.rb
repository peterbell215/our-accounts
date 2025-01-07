# frozen_string_literal: true
require 'csv'

# Factory that takes a CSV row and an ImportColumnsDefinition and generates an appropriate ImportedTransaction object
class ImportedTransactionFactory
  # @param [CSV::Row] csv_row
  # @param [ImportColumnsDefinition] import_columns_definition
  # @return [null, ImportedTransaction]
  def self.build(csv_row, import_columns_definition)
    imported_transaction = ImportedTransaction.new
    # TODO: replace with something that also checks the account columns if defined.
    imported_transaction.import_account_id = import_columns_definition.account.id

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

  # Determine the transaction amount.
  # @param [CSV::Row] csv_row
  # @param [ImportColumnsDefinition] import_columns_definition
  # @return [Money]
  def self.set_amount(csv_row, import_columns_definition)
    if (import_columns_definition.amount_column)
      amount = csv_row[import_columns_definition.amount_column]
    else
      amount = csv_row[import_columns_definition.credit_column] || -csv_row[import_columns_definition.debit_column]
      amount *= import_columns_definition.credit_sign
    end
    Money.from_amount(amount)
  end
end
