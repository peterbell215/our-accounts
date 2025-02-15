require 'rails_helper'

RSpec.describe Balances do
  let!(:lloyds_account) { BankAccount.find_by_name("Lloyds Account") || create(:lloyds_account) }

  before do
    create(:import_matcher_octopus_energy)
  end

  describe "it correctly imports the trx's" do
    subject!(:trx) { lloyds_account.add_transaction(imported_trx) }

    let(:imported_trx) { build(:octopus_energy_imported_trx, amount: amount, balance: balance) }
    let(:amount) { Money.from_amount(-50.00) }
    let(:balance) { lloyds_account.opening_balance + amount }

    specify("date") { expect(trx.date).to eql imported_trx.date }
    specify("account") { expect(trx.account_id).to eql lloyds_account.id }
    specify("amount") { expect(trx.amount).to eql amount }
    specify("other_party") { expect(trx.other_party_id).to eql TradingAccount.find_by_name("Octopus Energy").id }
    specify("category") { expect(trx.category_id).to eql Category.find_by_name("Utilities").id }
  end

  context 'when no previous transaction in account' do
    pending
  end
end
