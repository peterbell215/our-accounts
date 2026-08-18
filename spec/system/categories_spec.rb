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
