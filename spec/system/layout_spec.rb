require 'rails_helper'

RSpec.describe 'The menu bar', type: :system do
  let(:account) { create(:lloyds_account) }

  # A window short enough that the page itself has somewhere to scroll.
  def visit_a_page_worth_scrolling
    AccountTrxDataGenerator.new(account: account,
                                import_columns_definition_factory: :lloyds_import_columns_definition).generate

    page.driver.browser.manage.window.resize_to(1000, 400)
    visit account_path(account)
  end

  def menu_top
    page.evaluate_script("document.querySelector('nav').getBoundingClientRect().top")
  end

  # The other half of the promise: not merely in place, but nothing drawn over it.
  def menu_on_top?
    page.evaluate_script(<<~JS)
      (() => {
        const nav = document.querySelector('nav');
        const box = nav.getBoundingClientRect();
        const hit = document.elementFromPoint(box.left + 5, box.top + box.height / 2);
        return nav.contains(hit);
      })()
    JS
  end

  it 'stays at the top of the window while the page scrolls' do
    visit_a_page_worth_scrolling

    # Where the layout leaves it before anything scrolls is a styling detail — a page margin puts it a
    # few pixels down. The promise is what happens once the reader has scrolled past that.
    resting_top = menu_top
    page.execute_script("window.scrollTo(0, document.body.scrollHeight)")

    expect(page.evaluate_script("window.scrollY")).to be > resting_top
    expect(menu_top).to eq(0)
  end

  it 'is not covered by the transaction list passing underneath it' do
    visit_a_page_worth_scrolling
    page.execute_script("window.scrollTo(0, document.body.scrollHeight)")

    expect(menu_on_top?).to be true
  end
end
