require 'rails_helper'

RSpec.describe FileImporter, type: :class do
  subject { FileImporter.new('test.csv', lloyds_account) }

  let(:lloyds_account) { FactoryBot.create(:lloyds_account, with_import_columns_definition: true) }

  describe '#import_rows' do
    let(:csv_row) { CSV::Row.new(header, csv_data) }
    let(:header) { ["Transaction Date", "Transaction Type", "Sort Code", "Account Number", "Transaction Description", "Debit Amount", "Credit Amount", "Balance"] }
    let(:csv_data) { ["12/12/2024", "DEB","'30-00-00" ,"00000000" , "Maison Bertaux", 5.95, nil, 1525.80] }

    context 'when we provide a valid row' do
      let(:imported_transaction) { subject.import_row(csv_row) }

      specify { expect(imported_transaction.import_account_id).to eq(lloyds_account.id) }
      specify { expect(imported_transaction.date).to eq Date.new(2024,12,12) }
      specify { expect(imported_transaction.description).to eq("Maison Bertaux") }
      specify { expect(imported_transaction.trx_type).to eq("DEB") }
      specify { expect(imported_transaction.amount).to eq Money.from_amount(-5.95) }
      specify { expect(imported_transaction.balance).to eq Money.from_amount(1525.80) }
    end
  end
end