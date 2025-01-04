# frozen_string_literal: true

require 'rspec'

RSpec.describe 'FileImporter' do
  subject { FileImporter.new(:lloyds_test_account) }

  describe '#import_rows' do
    let(:csv_row) { CSV::Row.new(header, ["12/12/2024", "AMZNMktplace*2K3UV", "DEB", 0.0, 0.0, 0.0]) }
    let(:header) { ["Transaction Date", "Transaction Type", "Sort Code", "Account Number", "Transaction Description", "Debit Amount", "Credit Amount", "Balance"] }
    let(:csv_data) { ["12/12/2024", "DEB","'30-91-56" ,"00370982" , "Maison Bertaux", 5.95, nil, 1525.80] }
    

    
    context 'when we provide a valid row' do
      it 'generates an ImportedTransaction' do
        expect(subject.import_rows).to be_a(ImportedTransaction)
      end
    end
  end
end
