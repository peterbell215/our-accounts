require 'rails_helper'

RSpec.describe TransactionPage, type: :model do
  let(:account) { create(:lloyds_account) }

  # @param date [Date]
  # @param day_index [Integer, nil] nil mimics a transaction added by hand through the UI, which never
  #   runs Transaction#sequence
  def tx(date, day_index: 0, amount: -10.00)
    create(:transaction, account: account, date: date, day_index: day_index,
                         description: "TX #{date} #{day_index}", amount: Money.from_amount(amount))
  end

  describe 'a page of transactions' do
    before { 5.downto(1) { |n| tx(Date.new(2024, 6, n)) } }

    subject(:page) { described_class.new(account: account, size: 3) }

    it 'returns at most a page, newest first' do
      expect(page.transactions.map(&:date)).to eq([ Date.new(2024, 6, 5), Date.new(2024, 6, 4), Date.new(2024, 6, 3) ])
    end

    it 'reports that more remain' do
      expect(page).to be_more
    end

    it 'points the cursor at its last row' do
      last = page.transactions.last
      expect(page.next_cursor).to eq({ date: last.date, day_index: last.day_index, id: last.id })
    end

    it 'does not report more when the page covers everything' do
      expect(described_class.new(account: account, size: 10)).not_to be_more
    end
  end

  describe 'paging with the cursor' do
    before { 6.downto(1) { |n| tx(Date.new(2024, 6, n)) } }

    it 'resumes after the last row, without repeating or skipping' do
      first = described_class.new(account: account, size: 2)
      second = described_class.new(account: account, size: 2, cursor: first.next_cursor)
      third = described_class.new(account: account, size: 2, cursor: second.next_cursor)

      seen = (first.transactions + second.transactions + third.transactions).map(&:id)

      expect(seen).to eq(seen.uniq)
      expect(seen.size).to eq(6)
      expect(third).not_to be_more
    end

    it 'separates transactions sharing a date by day_index' do
      account.transactions.destroy_all
      3.times { |i| tx(Date.new(2024, 6, 1), day_index: i) }

      first = described_class.new(account: account, size: 2)
      second = described_class.new(account: account, size: 2, cursor: first.next_cursor)

      expect(first.transactions.map(&:day_index)).to eq([ 2, 1 ])
      expect(second.transactions.map(&:day_index)).to eq([ 0 ])
    end

    # Transactions added through the UI never run #sequence, so day_index is null. A keyset comparison
    # against null matches nothing, which would drop those rows from every page after the first.
    it 'still pages past transactions that have no day_index' do
      account.transactions.destroy_all
      tx(Date.new(2024, 6, 3), day_index: nil)
      tx(Date.new(2024, 6, 2), day_index: nil)
      tx(Date.new(2024, 6, 1), day_index: nil)

      first = described_class.new(account: account, size: 1)
      second = described_class.new(account: account, size: 1, cursor: first.next_cursor)

      expect(second.transactions.map(&:date)).to eq([ Date.new(2024, 6, 2) ])
      expect(second).to be_more
    end
  end

  describe 'the anchor' do
    before do
      tx(Date.new(2024, 6, 10))
      tx(Date.new(2024, 6, 5))
      tx(Date.new(2024, 6, 1))
    end

    it 'defaults to the account newest transaction' do
      expect(described_class.new(account: account).anchor).to eq(Date.new(2024, 6, 10))
    end

    it 'limits the window to transactions on or before it' do
      page = described_class.new(account: account, anchor: Date.new(2024, 6, 5))

      expect(page.transactions.map(&:date)).to eq([ Date.new(2024, 6, 5), Date.new(2024, 6, 1) ])
    end

    it 'accepts a date given as a string, as it arrives from a query parameter' do
      expect(described_class.new(account: account, anchor: "2024-06-05").anchor).to eq(Date.new(2024, 6, 5))
    end

    it 'falls back to the default when the parameter is not a date' do
      expect(described_class.new(account: account, anchor: "not-a-date").anchor).to eq(Date.new(2024, 6, 10))
    end

    it 'is clamped to the account range, so navigation cannot strand the reader' do
      expect(described_class.new(account: account, anchor: "2030-01-01").anchor).to eq(Date.new(2024, 6, 10))
      expect(described_class.new(account: account, anchor: "2000-01-01").anchor).to eq(Date.new(2024, 6, 1))
    end
  end

  describe 'moving the window' do
    before do
      tx(Date.new(2024, 6, 30))
      tx(Date.new(2024, 3, 15))
      tx(Date.new(2024, 1, 1))
    end

    subject(:page) { described_class.new(account: account, anchor: Date.new(2024, 3, 15)) }

    it 'steps back by a day, a week and a month' do
      expect(page.back(:day)).to eq(Date.new(2024, 3, 14))
      expect(page.back(:week)).to eq(Date.new(2024, 3, 8))
      expect(page.back(:month)).to eq(Date.new(2024, 2, 15))
    end

    it 'steps forward by a day, a week and a month' do
      expect(page.forward(:day)).to eq(Date.new(2024, 3, 16))
      expect(page.forward(:week)).to eq(Date.new(2024, 3, 22))
      expect(page.forward(:month)).to eq(Date.new(2024, 4, 15))
    end

    it 'clamps a step that would leave the account range' do
      earliest = described_class.new(account: account, anchor: Date.new(2024, 1, 1))
      latest = described_class.new(account: account, anchor: Date.new(2024, 6, 30))

      expect(earliest.back(:month)).to eq(Date.new(2024, 1, 1))
      expect(latest.forward(:month)).to eq(Date.new(2024, 6, 30))
    end

    it 'knows when it has reached either end' do
      expect(page).not_to be_at_earliest
      expect(page).not_to be_at_latest
      expect(described_class.new(account: account, anchor: Date.new(2024, 1, 1))).to be_at_earliest
      expect(described_class.new(account: account)).to be_at_latest
    end

    it 'rejects an unknown step' do
      expect { page.back(:fortnight) }.to raise_error(ArgumentError, /fortnight/)
    end
  end

  describe 'an account with no transactions' do
    subject(:page) { described_class.new(account: account) }

    it 'is empty and offers nothing to navigate' do
      expect(page.transactions).to be_empty
      expect(page).not_to be_any
      expect(page).not_to be_more
      expect(page.anchor).to be_nil
      expect(page.next_cursor).to be_nil
      expect(page.back(:day)).to be_nil
      expect(page).to be_at_earliest
      expect(page).to be_at_latest
    end
  end

  describe 'an anchor before any transaction exists' do
    before { tx(Date.new(2024, 6, 10)) }

    it 'clamps rather than returning an empty window' do
      page = described_class.new(account: account, anchor: "2020-01-01")

      expect(page.anchor).to eq(Date.new(2024, 6, 10))
      expect(page).to be_any
    end
  end
end
