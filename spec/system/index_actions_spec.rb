require 'rails_helper'

# Every list reads the same way: a heading naming it, everything the list can do under that, and the rows
# below both.  As with the Show and form screens, the promise is not merely that the buttons exist but
# where they are — these used to sit under the table, which on the counterparties list at 232 rows put
# every action two screens below the heading and out of sight from the moment you arrived.
RSpec.describe 'The actions on a list screen', type: :system do
  def element_box(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const box = document.querySelector('#{selector}').getBoundingClientRect();
        return { top: box.top, bottom: box.bottom };
      })()
    JS
  end

  # `data` is whatever holds the rows. Named per screen rather than assumed, because 'table' would match
  # the wrong thing on the rules list, which is a div-table, and on counterparties, where the table is
  # wrapped in the form the merge button submits.
  shared_examples 'a list screen' do |heading, action|
    it 'puts what the list can do between the heading and the rows' do
      visit path

      expect(page).to have_css('h1', text: heading)

      within('.index-actions') { expect(page).to have_link(action) }

      expect(element_box('h1')['bottom']).to be <= element_box('.index-actions')['top']
      expect(element_box('.index-actions')['bottom']).to be <= element_box(data)['top']
    end
  end

  describe 'the accounts list' do
    let(:path) { accounts_path }
    let(:data) { 'table' }
    before { create(:lloyds_account) }

    it_behaves_like 'a list screen', 'Accounts', 'New account'
  end

  describe 'the categories list' do
    let(:path) { categories_path }
    let(:data) { 'table' }

    it_behaves_like 'a list screen', 'Categories', 'New category'
  end

  describe 'the counterparties list' do
    let(:path) { counterparties_path }
    # The form the merge button reaches by id, which is what wraps the rows here.
    let(:data) { '#counterparty-merge' }
    before { create(:octopus_energy) }

    it_behaves_like 'a list screen', 'Counterparties', 'New counterparty'
    it_behaves_like 'a list screen', 'Counterparties', 'Suggest merges'

    # The one action on any list that is a submit rather than a link. It sits outside the form it drives —
    # the form stays wrapped around the table — and reaches it through HTML's `form` attribute, so this
    # asserts the association rather than trusting it.
    it 'carries the merge submit, which still drives the form below it' do
      create(:amazon)
      visit counterparties_path

      within('.index-actions') { expect(page).to have_button('Merge selected') }
      expect(page).to have_css('#counterparty-merge')
      expect(page.find('input[value="Merge selected"]')['form']).to eq 'counterparty-merge'

      all('input[type=checkbox]').each(&:check)
      click_button 'Merge selected'

      expect(page).to have_css('h1', text: /Merge \d+ counterparties/)
    end
  end

  describe 'the column definitions list' do
    let(:path) { import_columns_definitions_path }
    let(:data) { 'table' }
    before { create(:lloyds_import_columns_definition, account: create(:lloyds_account)) }

    it_behaves_like 'a list screen', 'Import columns definitions', 'New import columns definition'
  end

  # The only list reached from somewhere other than the menu bar, so the only one whose strip carries a
  # Back as well as its own actions. A menu-bar destination has nowhere to go back to.
  describe 'the rules list' do
    let(:account) { create(:lloyds_account) }
    let(:path) { account_import_matchers_path(account) }
    # The div-table renders only where the account has rules, so there has to be one to sit below.
    let(:data) { '.div-table' }
    before { create(:import_matcher_octopus_energy, account: account) }

    it_behaves_like 'a list screen', 'Import rules', 'New rule'

    it 'offers the way back up to its account' do
      visit path

      within('.index-actions') { click_link 'Back' }

      expect(page).to have_css('h1', text: account.name)
    end
  end

  # Reached from the counterparties list, so it has a Back too. Its only other action is per-row.
  describe 'the merge suggestions list' do
    let(:account) { create(:lloyds_account) }

    it 'offers the way back to the counterparties it is about' do
      allow(MergeSuggester).to receive(:new)
        .and_return(instance_double(MergeSuggester, groups: [], error: nil))

      visit merge_suggestions_path

      within('.index-actions') { click_link 'Back' }

      expect(page).to have_css('h1', text: 'Counterparties')
    end
  end
end
