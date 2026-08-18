require 'rails_helper'

# Every Show screen offers the same three actions, worded and placed the same way, so the reader learns
# them once.  Each example names the screen and the element holding the record's data, because the promise
# is not merely that the buttons exist but that they sit above the data rather than under it.
RSpec.describe 'The actions on a Show screen', type: :system do
  # The top of the first thing on the page that is the record itself rather than its title or its actions.
  def data_top(selector)
    page.evaluate_script("document.querySelector('#{selector}').getBoundingClientRect().top")
  end

  def actions_bottom
    page.evaluate_script("document.querySelector('.show-actions').getBoundingClientRect().bottom")
  end

  shared_examples 'a Show screen' do |data_selector|
    it 'offers Back, Edit and Destroy above the data' do
      visit path

      within('.show-actions') do
        expect(page).to have_link('Back')
        expect(page).to have_link('Edit')
        expect(page).to have_button('Destroy')
      end

      expect(actions_bottom).to be <= data_top(data_selector)
    end

    it 'asks before destroying the record' do
      visit path

      dismiss_confirm { click_button 'Destroy' }

      expect(page).to have_css('.show-actions')
    end
  end

  describe 'an account' do
    let(:path) { account_path(create(:lloyds_account)) }

    it_behaves_like 'a Show screen', '.account-grid'

    it 'offers the account-specific actions alongside the three' do
      visit path

      within('.show-actions') { expect(page).to have_link('Manage Import Rules') }
    end
  end

  describe 'a category' do
    let(:path) { category_path(create(:category)) }

    it_behaves_like 'a Show screen', '.category-grid'
  end

  describe 'a counterparty' do
    let(:path) { counterparty_path(create(:octopus_energy)) }

    # The name is the screen's heading, so the data proper starts at the transactions below it.
    it_behaves_like 'a Show screen', 'h2'
  end

  describe 'an import columns definition' do
    let(:path) { import_columns_definition_path(create(:lloyds_import_columns_definition)) }

    it_behaves_like 'a Show screen', '.import-columns-grid'
  end

  describe 'an import rule' do
    let(:matcher) { create(:import_matcher_octopus_energy) }
    let(:path) { account_import_matcher_path(matcher.account, matcher) }

    it_behaves_like 'a Show screen', 'dl'
  end
end
