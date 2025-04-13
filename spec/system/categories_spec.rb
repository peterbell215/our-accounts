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
end
