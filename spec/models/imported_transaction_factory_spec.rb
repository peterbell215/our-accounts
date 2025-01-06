require 'rails_helper'

require 'rails_helper'

RSpec.describe ImportedTransactionFactory, type: :model do
  let(:import_columns_definition) { FactoryBot.create(:lloyds_import_columns_definition)}

  let(:csv_row) { CSV::Row.new(header, csv_data) }
  let(:header) { ["Transaction Date", "Transaction Type", "Sort Code", "Account Number", "Transaction Description", "Debit Amount", "Credit Amount", "Balance"] }
  let(:csv_data) { ["12/12/2024", "DEB","'30-00-01" ,"01234567" , "Maison Bertaux", 5.95, nil, 1525.80] }

  describe '#build' do
    subject(:imported_transaction) { ImportedTransactionFactory.build(csv_row, import_columns_definition) }

    specify { expect(imported_transaction.import_account_id).to eq(1) }
    specify { expect(imported_transaction.date).to eq(Date.new(2024, 12, 12)) }
    specify { expect(imported_transaction.trx_type).to eq('DEB') }
    specify { expect(imported_transaction.description).to eq('Maison Bertaux') }
    specify { expect(imported_transaction.amount).to eq(Money.from_amount(-5.95)) }
    specify { expect(imported_transaction.balance).to eq(Money.from_amount(1525.80)) }
  end
end
