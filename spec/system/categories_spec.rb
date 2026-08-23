require 'rails_helper'

RSpec.describe 'Categories', type: :system do
  it 'allows a user to create a new category' do
    # Visit the new category page
    visit new_category_path

    # Fill in the form fields
    fill_in 'Name', with: 'Test Category'
    fill_in 'Description', with: 'This is a test category.'

    # Submit the form
    click_button 'Create Category'

    # Verify the category was created successfully
    expect(page).to have_content('Category was successfully created.')
    expect(page).to have_content('Test Category')

    # Verify the record was written to the database
    category = Category.find_by(name: 'Test Category')
    expect(category).not_to be_nil
    expect(category.description).to eq('This is a test category.')
  end

  it 'flags an error if no name is entered' do
    # Visit the new category page
    visit new_category_path

    # Leave the name field blank
    fill_in 'Name', with: ''
    fill_in 'Description', with: 'This is a test category.'

    # Submit the form
    click_button 'Create Category'

    # Verify that an error message is displayed
    expect(page).to have_content("Name can't be blank")
  end

  it 'renders the category details correctly' do
    # Create a test category in the database
    category = FactoryBot.create(:category, name: 'Test Category', description: 'This is a test category.')

    # Visit the category show page
    visit category_path(category)

    # Verify that the category details are displayed correctly
    expect(page).to have_content('Test Category')
    expect(page).to have_content('This is a test category.')
  end

  it 'allows a user to edit a category' do
    # Create a test category in the database
    category = FactoryBot.create(:category)

    # Visit the edit category page
    visit edit_category_path(category)

    # Update the category details
    fill_in 'Name', with: 'Updated Category'
    fill_in 'Description', with: 'Updated description.'

    # Submit the form
    click_button 'Update Category'

    # Verify the category was updated successfully
    expect(page).to have_content('Category was successfully updated.')
    expect(page).to have_content('Updated Category')

    # Verify the record was updated in the database
    category.reload
    expect(category.name).to eq('Updated Category')
    expect(category.description).to eq('Updated description.')
  end
  # A category answers "how is this forecast" already.  These two sections answer "who did I spend it with"
  # and "what files things here", the same pair of questions the counterparty screen answers the other way
  # round.
  describe 'the counterparties on a category' do
    let(:category) { Category.find_by!(name: 'Utilities') }
    let(:lloyds) { FactoryBot.create(:lloyds_account) }

    # Named so that alphabetical order and spend order disagree, so an assertion on the order means
    # something.
    let(:anvil) { FactoryBot.create(:counterparty, name: 'Anvil Works') }
    let(:zebra) { FactoryBot.create(:counterparty, name: 'Zebra Supplies') }

    def counterparty_names
      page.all('#category_counterparties tbody tr td:first-child').map(&:text)
    end

    it 'lists who was paid, how often and how much, with the largest spend first' do
      FactoryBot.create(:tesco_shop, account: lloyds, category: category, counterparty: anvil,
                                     date: Date.new(2024, 7, 1), amount: Money.from_amount(-5.95))
      FactoryBot.create(:tesco_shop, account: lloyds, category: category, counterparty: zebra,
                                     date: Date.new(2024, 7, 2), amount: Money.from_amount(-200.00))
      FactoryBot.create(:tesco_shop, account: lloyds, category: category, counterparty: zebra,
                                     date: Date.new(2024, 7, 3), amount: Money.from_amount(-100.00))

      visit category_path(category)

      expect(counterparty_names).to eq([ 'Zebra Supplies', 'Anvil Works' ])
      expect(page).to have_content('2 counterparties')

      # money-rails puts the sign inside the symbol.
      within("#counterparty_#{zebra.id}") do
        expect(page).to have_content('2')
        expect(page).to have_content('£-300.00')
      end
      within("#counterparty_#{anvil.id}") do
        expect(page).to have_content('£-5.95')
      end
    end

    # The link asked for: from a category to the supplier's own page, where every dealing with it across
    # all accounts is gathered.
    it 'follows a counterparty through to its own screen' do
      FactoryBot.create(:tesco_shop, account: lloyds, category: category, counterparty: anvil,
                                     date: Date.new(2024, 7, 1), amount: Money.from_amount(-5.95))

      visit category_path(category)
      click_link 'Anvil Works'

      expect(page).to have_current_path(counterparty_path(anvil))
      expect(page).to have_css('h1', text: 'Anvil Works')
    end

    # A category's transactions naming nobody is expected rather than a gap, so it is said rather than
    # left as a bare heading.
    it 'says so when nothing filed here names a counterparty' do
      FactoryBot.create(:tesco_shop, account: lloyds, category: category, counterparty: nil,
                                     date: Date.new(2024, 7, 1), amount: Money.from_amount(-5.95))

      visit category_path(category)

      expect(page).to have_content('No transaction filed under this category names a counterparty yet')
      expect(page).to have_no_css('#category_counterparties')
    end

    # The rules are the other reading of the same relationship, and they are what refuses a delete, so
    # seeing them here is what tells you which ones to deal with first.
    it 'lists the rules that assign the category, with the counterparty each names' do
      FactoryBot.create(:import_matcher_octopus_energy)

      visit category_path(category)

      within('#category_matchers') do
        expect(page).to have_content('OCTOPUS ENERGY')
        expect(page).to have_link('Octopus Energy', href: counterparty_path(Counterparty.find_by!(name: 'Octopus Energy')))
        expect(page).to have_link('Edit')
      end
    end

    # ImportMatcher#counterparty_id is nullable: AnalysisImporter still derives a rule from a description
    # too short to be an account name, and that rule still assigns this category.
    it 'shows a dash where a rule names no counterparty' do
      FactoryBot.create(:import_matcher_without_counterparty)

      visit category_path(category)

      within('#category_matchers') do
        expect(page).to have_content('O2')
        expect(page).to have_content('—')
      end
    end

    it 'says so when no rule assigns the category' do
      visit category_path(category)

      expect(page).to have_content('No import rule assigns this category')
      expect(page).to have_no_css('#category_matchers')
    end
  end

  describe 'ordering the list' do
    # The suite creates Shopping, Travel and Utilities before it runs, and they have no description, so
    # these two are named to bracket them alphabetically and given descriptions that sort the other way.
    before do
      Category.create!(name: 'zebra', description: 'Aardvark related')
      Category.create!(name: 'Anvil', description: 'Zoological')
      visit categories_path
    end

    def names
      page.all('#categories tbody tr td:first-child').map(&:text)
    end

    # Reading every cell would snapshot the old rows and go stale the moment a click reloads the page, so
    # wait for the row that should now be first before comparing the whole order.
    def expect_first(name)
      expect(page).to have_selector('#categories tbody tr:first-child td:first-child', text: name)
    end

    it 'is alphabetical to begin with, whatever case the names are in' do
      expect(names).to eq([ 'Anvil', 'Shopping', 'Travel', 'Utilities', 'zebra' ])
    end

    it 'reverses when the same heading is clicked again' do
      click_link 'Name'
      expect_first('zebra')

      expect(names).to eq([ 'zebra', 'Utilities', 'Travel', 'Shopping', 'Anvil' ])
    end

    # Where the categories with no description land is SQLite's business; what matters is that the two
    # that have one come out in their order.
    it 'orders by description when that heading is clicked' do
      click_link 'Description'
      expect(page).to have_link('Description ▲')

      expect(names.index('zebra')).to be < names.index('Anvil')

      click_link 'Description ▲'
      expect(page).to have_link('Description ▼')

      expect(names.index('Anvil')).to be < names.index('zebra')
    end

    it 'marks which column the order is on' do
      expect(page).to have_link('Name ▲')

      click_link 'Name ▲'

      expect(page).to have_link('Name ▼')
    end

    # The column name is interpolated into the ORDER BY, so anything but the two it knows is ignored.
    it 'ignores a column it does not offer' do
      visit categories_path(sort: 'id')

      expect(page).to have_link('Name ▲')
      expect(names).to eq([ 'Anvil', 'Shopping', 'Travel', 'Utilities', 'zebra' ])
    end
  end
end
