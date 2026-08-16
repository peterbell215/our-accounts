require 'rails_helper'

RSpec.describe 'Paging through an account transaction list', type: :system do
  let(:account) { create(:lloyds_account) }

  # Small pages, so the specs stay fast while still exercising more than one of them.
  before { stub_const("TransactionPage::SIZE", 3) }

  # Ten transactions, one a day, newest 2024-06-10.
  def ten_days_of_transactions
    10.downto(1) do |day|
      create(:transaction, account: account, date: Date.new(2024, 6, day), day_index: 0,
                           description: "PAYEE #{format('%02d', day)}",
                           amount: Money.from_amount(-10.00))
    end
  end

  def scroll_to_bottom
    page.execute_script("window.scrollTo(0, document.body.scrollHeight)")
  end

  describe 'loading on demand' do
    before do
      ten_days_of_transactions
      visit account_path(account)
    end

    it 'renders only the first page to begin with' do
      expect(page).to have_content("PAYEE 10")
      expect(page).to have_content("PAYEE 08")
      expect(page).to have_no_content("PAYEE 07")
    end

    it 'loads older transactions as the reader reaches the end' do
      scroll_to_bottom
      expect(page).to have_content("PAYEE 07")

      scroll_to_bottom
      expect(page).to have_content("PAYEE 04")
    end

    it 'stops once the history runs out, without repeating rows' do
      4.times do
        scroll_to_bottom
        sleep 0.3
      end

      expect(page).to have_content("PAYEE 01")
      expect(page).to have_css(".transaction-row", count: 10)
      expect(page).to have_no_css("[data-controller='transactions-pager']")
    end
  end

  describe 'moving the window by date' do
    before do
      ten_days_of_transactions
      visit account_path(account)
    end

    it 'starts at the most recent transaction' do
      expect(page).to have_content("on or before 10/06/2024")
    end

    it 'steps back a day' do
      click_link "« Day"

      expect(page).to have_content("on or before 09/06/2024")
      expect(page).to have_content("PAYEE 09")
      expect(page).to have_no_content("PAYEE 10")
    end

    it 'steps back a week' do
      click_link "« Week"

      expect(page).to have_content("on or before 03/06/2024")
      expect(page).to have_content("PAYEE 03")
      expect(page).to have_no_content("PAYEE 04")
    end

    it 'steps forward again' do
      click_link "« Week"
      click_link "Day »"

      expect(page).to have_content("on or before 04/06/2024")
    end

    it 'offers a way back to the newest transactions' do
      click_link "« Week"
      click_link "jump to latest"

      expect(page).to have_content("on or before 10/06/2024")
      expect(page).to have_content("PAYEE 10")
    end

    it 'disables the steps that would leave the account range' do
      # Already at the newest transaction, so forward is not available.
      expect(page).to have_no_link("Day »")
      expect(page).to have_css("span.pure-button-disabled", text: "Day »")
      expect(page).to have_link("« Day")
    end

    it 'clamps a step that would run past the oldest transaction' do
      click_link "« Month"

      expect(page).to have_content("on or before 01/06/2024")
      expect(page).to have_css("span.pure-button-disabled", text: "« Month")
    end
  end

  describe 'an account whose transactions all predate the window' do
    it 'reports plainly that there is nothing to show' do
      visit account_path(account)

      expect(page).to have_content("No transactions found for this account.")
    end
  end
end
