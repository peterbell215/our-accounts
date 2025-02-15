require 'rails_helper'

RSpec.describe Balances do
  let!(:lloyds_account) { BankAccount.find_by_name("Lloyds Account") || create(:lloyds_account) }

  before do
    create(:import_matcher_octopus_energy)
  end

  context 'when no previous transaction in account' do
    subject!(:trx) { lloyds_account.add_transaction(imported_trx) }

    let(:imported_trx) { build(:octopus_energy_imported_trx, amount: amount, balance: balance) }
    let(:amount) { Money.from_amount(-50.00) }
    let(:balance) { lloyds_account.opening_balance + amount }

    describe 'it correctly imports the trx' do
      specify { expect(trx.date).to eql imported_trx.date }
    end
  end
end