require 'rails_helper'

# Every Show screen reads the same way: a heading naming the record, the same three actions under it, and
# the record's data below both.  Each example names the screen's heading and the element holding its data,
# because the promise is not merely that the buttons exist but where they are — the geometry is the point.
RSpec.describe 'The actions on a Show screen', type: :system do
  def element_box(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const box = document.querySelector('#{selector}').getBoundingClientRect();
        return { top: box.top, bottom: box.bottom };
      })()
    JS
  end

  shared_examples 'a Show screen' do |heading, data_selector|
    it 'offers Back, Edit and Destroy between the heading and the data' do
      visit path

      expect(page).to have_css('h1', text: heading)
      expect(page).to have_title(heading)

      within('.show-actions') do
        expect(page).to have_link('Back')
        expect(page).to have_link('Edit')
        expect(page).to have_button('Destroy')
      end

      expect(element_box('h1')['bottom']).to be <= element_box('.show-actions')['top']
      expect(element_box('.show-actions')['bottom']).to be <= element_box(data_selector)['top']
    end

    it 'asks before destroying the record' do
      visit path

      dismiss_confirm { click_button 'Destroy' }

      expect(page).to have_css('.show-actions')
    end
  end

  describe 'an account' do
    let(:path) { account_path(create(:lloyds_account)) }

    it_behaves_like 'a Show screen', 'Lloyds Account', '.account-grid'

    it 'offers the account-specific actions alongside the three' do
      visit path

      within('.show-actions') { expect(page).to have_link('Manage Import Rules') }
    end
  end

  describe 'a category' do
    let(:path) { category_path(create(:category)) }

    it_behaves_like 'a Show screen', 'Test Category', '.category-grid'
  end

  describe 'a counterparty' do
    let(:path) { counterparty_path(create(:octopus_energy)) }

    # The heading is the name, so the data proper starts at the transactions below it.
    it_behaves_like 'a Show screen', 'Octopus Energy', 'h2'
  end

  describe 'an import columns definition' do
    let(:path) { import_columns_definition_path(create(:lloyds_import_columns_definition)) }

    # It has no name of its own, so it is headed by the account whose statements it describes.
    it_behaves_like 'a Show screen', 'Import columns for Lloyds Account', '.import-columns-grid'
  end

  describe 'an import rule' do
    let(:matcher) { create(:import_matcher_octopus_energy) }
    let(:path) { account_import_matcher_path(matcher.account, matcher) }

    it_behaves_like 'a Show screen', 'Rule for Lloyds Account', 'dl'
  end
end
