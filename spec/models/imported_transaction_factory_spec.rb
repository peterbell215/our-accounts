require 'rails_helper'

RSpec.describe ImportedTransactionFactory, type: :model do
  describe 'Lloyds Import' do
    subject(:imported_transaction) { ImportedTransactionFactory.build(csv_row, import_columns_definition) }

    let(:import_columns_definition) { FactoryBot.create(:lloyds_import_columns_definition) }

    let(:csv_row) { CSV::Row.new(header, csv_data, true) }
    let(:header) { [ "Transaction Date", "Transaction Type", "Sort Code", "Account Number", "Transaction Description", "Debit Amount", "Credit Amount", "Balance" ] }
    let(:account) { Account.find_by(name: "Lloyds Account") }

    describe '#build for debit' do
      let(:csv_data) { [ "12/12/2024", "DEB", "'30-00-00", "01234567", "Maison Bertaux", 5.95, nil, 1525.80 ] }

      specify { expect(imported_transaction.account_id).to eq(account.id) }
      specify { expect(imported_transaction.date).to eq(Date.new(2024, 12, 12)) }
      specify { expect(imported_transaction.trx_type).to eq('DEB') }
      specify { expect(imported_transaction.description).to eq('Maison Bertaux') }
      specify { expect(imported_transaction.amount).to eq(Money.from_amount(-5.95)) }
      specify { expect(imported_transaction.balance).to eq(Money.from_amount(1525.80)) }
    end

    describe '#build for credit' do
      let(:csv_data) { [ "23/12/2024", "BGC", "'30-00-00", "01234567", "EMPLOYER CURRENT", nil, 1200, 2525.80 ] }

      specify { expect(imported_transaction.account_id).to eq(account.id) }
      specify { expect(imported_transaction.date).to eq(Date.new(2024, 12, 23)) }
      specify { expect(imported_transaction.trx_type).to eq('BGC') }
      specify { expect(imported_transaction.description).to eq('EMPLOYER CURRENT') }
      specify { expect(imported_transaction.amount).to eq(Money.from_amount(1200)) }
      specify { expect(imported_transaction.balance).to eq(Money.from_amount(2525.80)) }
    end

    describe '#build raises AccountError' do
      let(:csv_data) { [ "12/12/2024", "DEB", "'30-00-01", "01234567", "Maison Bertaux", 5.95, nil, 1525.80 ] }

      it 'raises an AccountError when account details do not match' do
        expect { ImportedTransactionFactory.build(csv_row, import_columns_definition) }.to raise_error(ImportError, "Sortcode and/or account number do not match with input file")
      end
    end
  end

  describe 'Barclaycard Import' do
    let(:import_columns_definition) { FactoryBot.create(:barclaycard_import_columns_definition) }

    let(:csv_row) { CSV::Row.new([], csv_data) }
    let(:csv_data) { [ "01 Dec 24", " Norton *AP1563501329, Dublin99.99 POUND STERLING IRELAND ", "Visa", "MR C BELL", "Shopping", nil, 99.99 ] }
    let(:account) { Account.find_by(name: "Barclaycard") }

    describe '#build' do
      subject(:imported_transaction) { ImportedTransactionFactory.build(csv_row, import_columns_definition) }

      specify { expect(imported_transaction.account_id).to eq(account.id) }
      specify { expect(imported_transaction.date).to eq(Date.new(2024, 12, 1)) }
      specify { expect(imported_transaction.trx_type).to eq('Shopping') }
      specify { expect(imported_transaction.description).to eq(" Norton *AP1563501329, Dublin99.99 POUND STERLING IRELAND ") }
      specify { expect(imported_transaction.amount).to eq(Money.from_amount(-99.99)) }
      specify { expect(imported_transaction.balance).to be_nil }
    end
  end
end
