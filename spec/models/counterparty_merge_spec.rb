require 'rails_helper'

RSpec.describe CounterpartyMerge, type: :model do
  let(:lloyds) { create(:lloyds_account) }
  let(:utilities) { Category.find_by!(name: "Utilities") }
  let(:travel) { Category.find_by!(name: "Travel") }

  # A counterparty as the analysis import leaves one: named after statement text, with a rule and some
  # transactions behind it.
  def counterparty(name, transactions: 1, category: utilities, account: lloyds)
    Counterparty.create!(name: name).tap do |cp|
      create(:import_matcher, description: name, category: category, counterparty: cp, account: account)
      transactions.times do |i|
        create(:tesco_shop, account: account, counterparty: cp, date: Date.new(2024, 7, 1) + i)
      end
    end
  end

  describe 'folding a group together' do
    let!(:first) { counterparty("TESCO STORES 2228", transactions: 3) }
    let!(:second) { counterparty("TESCO STORES 2889", transactions: 2) }

    subject(:merge) { described_class.new(ids: [ first.id, second.id ], name: "Tesco") }

    it 'succeeds' do
      expect(merge.merge).to be true
      expect(merge.error).to be_nil
    end

    it 'moves every transaction onto the survivor' do
      merge.merge

      expect(first.reload.counterparty_transactions.count).to eq 5
      expect(merge.transactions_moved).to eq 2
    end

    it 'moves the rules too' do
      merge.merge

      expect(first.reload.counterparty_matchers.count).to eq 2
      expect(merge.matchers_moved).to eq 1
    end

    it 'keeps the lowest id, which is what Account.named already resolves to' do
      merge.merge

      expect(merge.survivor).to eq first
      expect(Counterparty.exists?(second.id)).to be false
    end

    it 'renames the survivor' do
      merge.merge

      expect(first.reload.name).to eq "Tesco"
    end

    it 'destroys no transactions' do
      expect { merge.merge }.not_to change(Transaction, :count)
    end

    it 'destroys no rules' do
      expect { merge.merge }.not_to change(ImportMatcher, :count)
    end
  end

  # Both of these fail if the steps happen in the wrong order, and in a way nothing else would notice.
  describe 'the ordering traps' do
    it 'leaves no transaction stranded without a counterparty' do
      first = counterparty("WAITROSE 651", transactions: 2)
      second = counterparty("WAITROSE 108", transactions: 2)

      described_class.new(ids: [ first.id, second.id ], name: "Waitrose").merge

      # Destroying a loser before re-pointing would nullify these, because both counterparty associations
      # are dependent: :nullify.
      expect(Transaction.where(counterparty_id: nil)).to be_empty
      expect(first.reload.counterparty_transactions.count).to eq 4
    end

    # The order of creation matters to this test.  The wanted name has to be held by a *loser*, not by the
    # survivor: a record is excluded from its own uniqueness check, so renaming the survivor to what it is
    # already called collides with nothing and would pass whatever the order.
    it 'takes a name that one of the losers was holding' do
      via_paypal = counterparty("PAYPAL *SPOTIFY", transactions: 3)   # lower id, so the survivor
      spotify = counterparty("SPOTIFY", transactions: 2)              # holds the name we want
      merge = described_class.new(ids: [ via_paypal.id, spotify.id ], name: "Spotify")

      # Renaming before the losers are destroyed fails uniqueness against a record about to disappear.
      expect(merge.merge).to be true
      expect(merge.error).to be_nil
      expect(merge.survivor).to eq via_paypal
      expect(merge.survivor.reload.name).to eq "Spotify"
      expect(merge.survivor.counterparty_transactions.count).to eq 5
    end
  end

  describe 'a name held outside the set' do
    let!(:spotify) { counterparty("SPOTIFY", transactions: 2) }
    let!(:via_paypal) { counterparty("PAYPAL *SPOTIFY", transactions: 3) }
    let!(:other) { counterparty("PAYPAL *LINKEDIN", transactions: 1) }

    subject(:merge) { described_class.new(ids: [ via_paypal.id, other.id ], name: "Spotify") }

    it 'is refused' do
      expect(merge.merge).to be false
    end

    it 'says which record holds the name, so including it is the obvious fix' do
      merge.merge

      expect(merge.error).to include("SPOTIFY")
      expect(merge.error).to include("Include it in the merge")
    end

    it 'changes nothing at all' do
      merge.merge

      expect(via_paypal.reload.counterparty_transactions.count).to eq 3
      expect(other.reload.counterparty_transactions.count).to eq 1
      expect(Counterparty.exists?(other.id)).to be true
      expect(merge.transactions_moved).to eq 0
    end
  end

  describe 'what it refuses' do
    let!(:only_one) { counterparty("TESCO STORES 2228") }

    it 'will not merge a set of one' do
      merge = described_class.new(ids: [ only_one.id ], name: "Tesco")

      expect(merge.merge).to be false
      expect(merge.error).to match(/at least 2/)
    end

    it 'will not merge nothing' do
      expect(described_class.new(ids: [], name: "Tesco").merge).to be false
    end

    # Transaction#counterparty is declared class_name: "Account", so without the Counterparty scope a
    # hand-edited form could fold away the account holding every transaction.
    it 'ignores an id that is one of the household’s own accounts' do
      second = counterparty("TESCO STORES 2889")
      merge = described_class.new(ids: [ only_one.id, second.id, lloyds.id ], name: "Tesco")

      expect(merge.counterparties).to contain_exactly(only_one, second)
      merge.merge

      expect(Account.exists?(lloyds.id)).to be true
      expect(lloyds.reload.name).to eq "Lloyds Account"
    end

    it 'needs a name' do
      second = counterparty("TESCO STORES 2889")
      merge = described_class.new(ids: [ only_one.id, second.id ], name: "  ")

      expect(merge.merge).to be false
      expect(merge.error).to match(/name/i)
    end

    it 'needs a name Account would accept' do
      second = counterparty("TESCO STORES 2889")
      merge = described_class.new(ids: [ only_one.id, second.id ], name: "T")

      expect(merge.merge).to be false
      expect(merge.error).to match(/between 3 and 50/)
      expect(Counterparty.exists?(second.id)).to be true
    end
  end

  # One payee can legitimately span categories — a gym that also runs a café — so a clash is a warning to
  # show, never a reason to refuse.
  describe 'categories' do
    let!(:gym) { counterparty("DAVID LLOYD", transactions: 2, category: travel) }
    let!(:leisure) { counterparty("DAVID LLOYD LEISUR", transactions: 2, category: utilities) }

    subject(:merge) { described_class.new(ids: [ gym.id, leisure.id ], name: "David Lloyd") }

    it 'reports the clash' do
      expect(merge).to be_categories_clash
      expect(merge.rule_categories).to eq [ "Travel", "Utilities" ]
    end

    it 'merges anyway' do
      expect(merge.merge).to be true
    end

    it 'leaves every rule with the category it had' do
      merge.merge

      expect(gym.reload.counterparty_matchers.map { |m| m.category.name }).to contain_exactly("Travel", "Utilities")
    end

    it 'does not report a clash when the rules agree' do
      one = counterparty("LNK TESCO MILTON", category: travel)
      two = counterparty("LNK NOTEMACHINE", category: travel)

      expect(described_class.new(ids: [ one.id, two.id ], name: "ATM")).not_to be_categories_clash
    end
  end
end
