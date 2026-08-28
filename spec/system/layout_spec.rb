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

  # Your own login is at the far end, away from the five screens the application is about.  By geometry
  # rather than by order in the document, because what is promised is where it is drawn: the flex rule
  # that puts it there is the whole of the change, and a plain `have_link` would pass without it.
  it 'keeps the way to your own login at the far end of the bar, inside it' do
    visit account_path(account)

    boxes = page.evaluate_script(<<~JS)
      (() => {
        const box = (sel) => {
          const r = document.evaluate(sel, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null)
            .singleNodeValue.getBoundingClientRect();
          return { left: r.left, right: r.right, top: r.top, bottom: r.bottom };
        };
        const nav = document.querySelector('nav').getBoundingClientRect();
        return {
          columns: box("//nav//a[normalize-space()='Input Columns Definition']"),
          out: box("//nav//a[normalize-space()='Sign out']"),
          nav: { left: nav.left, right: nav.right, top: nav.top, bottom: nav.bottom }
        };
      })()
    JS

    expect(boxes['out']['left']).to be > boxes['columns']['right']
    expect(boxes['out']['right']).to be <= boxes['nav']['right']
    expect(boxes['out']['bottom']).to be <= boxes['nav']['bottom']
  end

  it 'is not covered by the transaction list passing underneath it' do
    visit_a_page_worth_scrolling
    page.execute_script("window.scrollTo(0, document.body.scrollHeight)")

    expect(menu_on_top?).to be true
  end
end
