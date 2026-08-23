require 'rails_helper'

# Every New and Edit screen reads the same way: a heading naming what is being done, the way back under it,
# and the form below both.  As with the Show screens, the promise is not merely that the links exist but
# where they are — these used to sit at the very bottom of the page, which on the one form with a list
# beneath it put them off the end of the screen entirely.
RSpec.describe 'The actions on a form screen', type: :system do
  def element_box(selector)
    page.evaluate_script(<<~JS)
      (() => {
        const box = document.querySelector('#{selector}').getBoundingClientRect();
        return { top: box.top, bottom: box.bottom };
      })()
    JS
  end

  # The form is the data here.  Addressed as 'form' rather than by an h2: the edit paths render a flash
  # through layouts/_notice inside an h2 *above* the strip, and querySelector takes the first match.
  shared_examples 'a form screen' do |heading|
    it 'offers the way back between the heading and the form' do
      visit path

      expect(page).to have_css('h1', text: heading)

      within('.form-actions') { expect(page).to have_link('Back') }

      expect(element_box('h1')['bottom']).to be <= element_box('.form-actions')['top']
      expect(element_box('.form-actions')['bottom']).to be <= element_box('form')['top']
    end
  end

  # A New screen has no record to look at yet, so it offers Back and nothing else.
  shared_examples 'a New screen' do |heading|
    it_behaves_like 'a form screen', heading

    it 'does not offer Show, there being no record yet' do
      visit path

      within('.form-actions') { expect(page).to have_no_link('Show') }
    end
  end

  # An Edit screen offers both, and Show reaches the record as it currently stands.
  shared_examples 'an Edit screen' do |heading, record_heading|
    it_behaves_like 'a form screen', heading

    it 'offers Show as well, reaching the record itself' do
      visit path

      within('.form-actions') { click_link 'Show' }

      expect(page).to have_css('h1', text: record_heading)
    end
  end

  describe 'a new account' do
    let(:path) { new_account_path }

    it_behaves_like 'a New screen', 'New account'
  end

  describe 'an account being edited' do
    let(:path) { edit_account_path(create(:lloyds_account)) }

    it_behaves_like 'an Edit screen', 'Editing account', 'Lloyds Account'
  end

  describe 'a new category' do
    let(:path) { new_category_path }

    it_behaves_like 'a New screen', 'New category'
  end

  describe 'a category being edited' do
    let(:path) { edit_category_path(create(:category)) }

    it_behaves_like 'an Edit screen', 'Editing category', 'Test Category'
  end

  # The screen that prompted all this: predicted by its regular payments, so the form is followed by the
  # table of them and two paragraphs of explanation.  The way back has to be above all of it.
  describe 'a category whose edit screen carries a list of payments' do
    let(:path) { edit_category_path(create(:subscriptions_category)) }

    it_behaves_like 'an Edit screen', 'Editing category', 'Subscriptions'

    # Reached by a direct visit, so there is no flash, and the only h2 on the page is the payments section
    # the links used to sit underneath.
    it 'keeps the actions above the payments section, not below it' do
      visit path

      expect(page).to have_css('h2', text: 'Its regular payments')
      expect(element_box('.form-actions')['bottom']).to be <= element_box('h2')['top']
    end
  end

  describe 'a new counterparty' do
    let(:path) { new_counterparty_path }

    it_behaves_like 'a New screen', 'New counterparty'
  end

  describe 'a counterparty being edited' do
    let(:path) { edit_counterparty_path(create(:octopus_energy)) }

    it_behaves_like 'an Edit screen', 'Editing counterparty', 'Octopus Energy'
  end

  describe 'a new import columns definition' do
    let(:path) { new_import_columns_definition_path }

    it_behaves_like 'a New screen', 'New import columns definition'
  end

  describe 'an import columns definition being edited' do
    let(:path) { edit_import_columns_definition_path(create(:lloyds_import_columns_definition)) }

    it_behaves_like 'an Edit screen', 'Editing import columns definition',
                    'Import columns for Lloyds Account'
  end

  describe 'a new rule' do
    let(:path) { new_account_import_matcher_path(create(:lloyds_account)) }

    it_behaves_like 'a New screen', 'New rule for Lloyds Account'
  end

  # This is the one screen that gained a link rather than having one moved: it offered no way to reach the
  # rule it was editing.
  describe 'a rule being edited' do
    let(:matcher) { create(:import_matcher_octopus_energy) }
    let(:path) { edit_account_import_matcher_path(matcher.account, matcher) }

    it_behaves_like 'an Edit screen', 'Editing rule for Lloyds Account', 'Rule for Lloyds Account'
  end

  # The merge confirmation keeps its own Cancel beside Merge — that is its answer to the question it asks —
  # but the way out is where it is on every other screen.
  describe 'the merge confirmation' do
    let(:counterparties) { [ create(:octopus_energy), create(:amazon) ] }

    it 'offers the way back above the names it is about to fold together' do
      visit new_counterparty_merge_path(ids: counterparties.map(&:id))

      within('.form-actions') { expect(page).to have_link('Back') }
      expect(element_box('.form-actions')['bottom']).to be <= element_box('#merge_members')['top']

      within('.form-actions') { click_link 'Back' }

      expect(page).to have_css('h1', text: 'Counterparties')
    end
  end

  # The rules list is the only index reached from somewhere other than the menu bar, so the only one with
  # anywhere to go back to.
  describe 'the rules list' do
    let(:account) { create(:lloyds_account) }

    it 'offers the way back up to its account' do
      visit account_import_matchers_path(account)

      within('.form-actions') { click_link 'Back' }

      expect(page).to have_css('h1', text: account.name)
    end
  end
end
