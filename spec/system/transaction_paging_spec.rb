require 'rails_helper'

RSpec.describe 'Paging through an account transaction list', type: :system do
  let(:account) { create(:lloyds_account) }

  # A small window, so the specs stay fast while still sliding it several times.
  let(:window) { 6 }

  before { stub_const("TransactionPage::SIZE", window) }

  # Thirty transactions, one a day, newest 2024-06-30.
  def thirty_days_of_transactions
    30.downto(1) do |day|
      create(:transaction, account: account, date: Date.new(2024, 6, day), day_index: 0,
                           description: "PAYEE #{format('%02d', day)}",
                           amount: Money.from_amount(-10.00))
    end
  end

  def scroll_list(to:)
    page.execute_script(<<~JS)
      const box = document.querySelector('.transaction-scroll');
      box.scrollTop = #{to == :bottom ? 'box.scrollHeight' : '0'};
      box.dispatchEvent(new Event('scroll'));
    JS
    sleep 0.15
  end

  # Scrolls repeatedly until the block is satisfied.
  #
  # The number of scrolls needed is not fixed: a scroll that arrives while a fetch is still in flight
  # slides nothing, and how often that happens depends on how quickly the machine answers. Polling on the
  # outcome keeps the spec honest about what it is asserting instead of tuning an iteration count to one
  # machine.
  def scroll_until(to:, description:, limit: 60)
    limit.times do
      return if yield

      scroll_list to: to
    end

    raise "gave up waiting for #{description}; rendered #{rendered_payees.inspect}"
  end

  def scroll_to_oldest
    scroll_until(to: :bottom, description: "the oldest transaction") { page.has_content?("PAYEE 01", wait: 0.1) }
  end

  def scroll_to_newest
    scroll_until(to: :top, description: "the newest transaction") { page.has_content?("PAYEE 30", wait: 0.1) }
  end

  # Indexed among the cells rather than by nth-child, because form_with emits its hidden inputs as the
  # first children of the row. Cell 0 is the date, cell 1 the description.
  def rendered_payees
    page.all(".transaction-row").map { |row| row.all(".div-table-col")[1].text }
  end

  def fetch_count
    page.find(".transaction-scroll")["data-transactions-list-fetches-value"].to_i
  end

  describe 'the number of rendered rows' do
    before do
      thirty_days_of_transactions
      visit account_path(account)
    end

    it 'starts at one window' do
      expect(page).to have_css(".transaction-row", count: window)
    end

    it 'never exceeds one window, however far the reader scrolls' do
      12.times do
        scroll_list to: :bottom
        expect(page.all(".transaction-row").count).to be <= window
      end
    end

    it 'still holds one window after scrolling back up again' do
      scroll_to_oldest
      scroll_to_newest

      expect(page).to have_css(".transaction-row", count: window)
    end
  end

  describe 'sliding the window' do
    before do
      thirty_days_of_transactions
      visit account_path(account)
    end

    it 'shows the newest transactions first' do
      expect(rendered_payees.first).to eq("PAYEE 30")
      expect(page).to have_no_content("PAYEE 24")
    end

    it 'reveals older transactions as the reader reaches the bottom' do
      scroll_list to: :bottom

      expect(page).to have_content("PAYEE 24")
      expect(page).to have_no_content("PAYEE 30")
    end

    it 'reaches the oldest transaction eventually' do
      scroll_to_oldest

      expect(page).to have_content("PAYEE 01")
    end

    it 'stops at the oldest transaction rather than emptying the list' do
      scroll_to_oldest
      3.times { scroll_list to: :bottom }

      expect(page).to have_css(".transaction-row", count: window)
      expect(page).to have_content("PAYEE 01")
    end

    it 'brings back the newer transactions when the reader scrolls up' do
      3.times { scroll_list to: :bottom }
      expect(page).to have_no_content("PAYEE 30")

      scroll_to_newest

      expect(page).to have_content("PAYEE 30")
    end
  end

  describe 'rows already fetched' do
    before do
      thirty_days_of_transactions
      visit account_path(account)
    end

    it 'are kept in memory, so scrolling back asks the server for nothing' do
      scroll_to_oldest
      after_scrolling_down = fetch_count
      expect(after_scrolling_down).to be > 0

      scroll_to_newest

      expect(fetch_count).to eq(after_scrolling_down)
      expect(page).to have_content("PAYEE 30")
    end

    it 'keep any category the reader had chosen but not yet saved' do
      travel = Category.find_by!(name: "Travel")

      within(page.all(".transaction-row").first) do
        find("select").select(travel.name)
      end

      2.times { scroll_list to: :bottom }
      scroll_to_newest

      expect(page.all(".transaction-row").first.find("select").value).to eq(travel.id.to_s)
    end
  end

  describe 'moving the window by date' do
    before do
      thirty_days_of_transactions
      visit account_path(account)
    end

    it 'starts at the most recent transaction' do
      expect(page).to have_content("on or before 30/06/2024")
    end

    it 'steps back a day' do
      click_link "« Day"

      expect(page).to have_content("on or before 29/06/2024")
      expect(rendered_payees.first).to eq("PAYEE 29")
    end

    it 'steps back a week, and forward again' do
      click_link "« Week"
      expect(page).to have_content("on or before 23/06/2024")

      click_link "Day »"
      expect(page).to have_content("on or before 24/06/2024")
    end

    it 'does not accumulate rows across a jump' do
      scroll_to_oldest
      click_link "« Week"

      expect(page).to have_css(".transaction-row", count: window)
    end

    it 'offers a way back to the newest transactions' do
      click_link "« Week"
      click_link "jump to latest"

      expect(page).to have_content("on or before 30/06/2024")
    end

    it 'disables the steps that would leave the account range' do
      expect(page).to have_no_link("Day »")
      expect(page).to have_css("span.pure-button-disabled", text: "Day »")
      expect(page).to have_link("« Day")
    end
  end

  describe 'an account with no transactions' do
    it 'reports plainly that there is nothing to show' do
      visit account_path(account)

      expect(page).to have_content("No transactions found for this account.")
    end
  end
end
