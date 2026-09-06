require 'rails_helper'

RSpec.describe 'Merging counterparties', type: :system do
  let(:lloyds) { FactoryBot.create(:lloyds_account) }
  let(:utilities) { Category.find_by!(name: "Utilities") }
  let(:travel) { Category.find_by!(name: "Travel") }

  # A counterparty as the analysis import leaves one: named after statement text, with a rule behind it.
  def counterparty(name, transactions: 1, category: utilities)
    Counterparty.create!(name: name).tap do |cp|
      FactoryBot.create(:import_matcher, description: name, category: category,
                                         counterparty: cp, account: lloyds)
      transactions.times do |i|
        FactoryBot.create(:tesco_shop, account: lloyds, counterparty: cp, date: Date.new(2024, 7, 1) + i)
      end
    end
  end

  # exact: true because Capybara matches labels by substring by default, and this feature exists precisely
  # for names where one contains another — TESCO STORES beside TESCO STORES 2228 would otherwise raise
  # Capybara::Ambiguous the day such a pair reaches a system example.
  def tick(counterparty)
    check "Merge #{counterparty.name}", exact: true
  end

  it 'folds two names into one from the list' do
    first = counterparty("TESCO STORES 2228", transactions: 3)
    second = counterparty("TESCO STORES 2889", transactions: 2)

    visit counterparties_path
    tick first
    tick second
    click_button 'Merge selected'

    expect(page).to have_content('Merge 2 counterparties')
    expect(page).to have_content('TESCO STORES 2228')
    expect(page).to have_content('TESCO STORES 2889')

    fill_in 'name', with: 'Tesco'
    click_button 'Merge'

    expect(page).to have_content('Merged into Tesco')
    expect(page).to have_content('5 transactions')
    expect(first.reload.name).to eq 'Tesco'
    expect(Counterparty.exists?(second.id)).to be false
  end

  # The case the user actually has: five cash machines that are one counterparty under a name none of them
  # currently holds.
  it 'accepts a name none of them had' do
    machines = [ "LNK TESCO MILTON", "LNK NOTEMACHINE", "LNK SAINSBURYS BAN" ].map do |name|
      counterparty(name, transactions: 2, category: travel)
    end

    visit counterparties_path
    machines.each { |m| tick m }
    click_button 'Merge selected'

    fill_in 'name', with: 'ATM'
    click_button 'Merge'

    expect(page).to have_content('Merged into ATM')
    atm = Counterparty.find_by!(name: 'ATM')
    expect(atm.counterparty_transactions.count).to eq 6
    expect(atm.counterparty_matchers.count).to eq 3
  end

  it 'warns when the members do not agree on a category, and merges anyway' do
    groceries = counterparty("TESCO STORES 2228", transactions: 2, category: utilities)
    petrol = counterparty("TESCO PAY AT PUMP", transactions: 2, category: travel)

    visit counterparties_path
    tick groceries
    tick petrol
    click_button 'Merge selected'

    within('#category_clash') do
      expect(page).to have_content('do not agree on a category')
      expect(page).to have_content('Travel and Utilities')
    end

    fill_in 'name', with: 'Tesco'
    click_button 'Merge'

    expect(page).to have_content('Merged into Tesco')
    # Each rule keeps the category it had; that is the whole point of warning rather than refusing.
    expect(groceries.reload.counterparty_matchers.map { |m| m.category.name })
      .to contain_exactly('Utilities', 'Travel')
  end

  it 'says so when only one is ticked' do
    only = counterparty("TESCO STORES 2228")
    counterparty("WAITROSE 651")

    visit counterparties_path
    tick only
    click_button 'Merge selected'

    expect(page).to have_content('Tick at least 2 counterparties')
    expect(only.reload.name).to eq 'TESCO STORES 2228'
  end

  it 'keeps the selection when the name is already held by something outside the group' do
    first = counterparty("WAITROSE 651", transactions: 2)
    second = counterparty("WAITROSE 108", transactions: 2)
    counterparty("Waitrose")

    visit counterparties_path
    tick first
    tick second
    click_button 'Merge selected'

    fill_in 'name', with: 'Waitrose'
    click_button 'Merge'

    expect(page).to have_content('already held by')
    expect(page).to have_content('Include it in the merge')
    # Back on the confirmation with both still listed, so the name can be corrected rather than re-ticked.
    expect(page).to have_content('WAITROSE 651')
    expect(page).to have_content('WAITROSE 108')
    expect(Counterparty.exists?(second.id)).to be true
  end
  # Working through a list of suggestions one group at a time. Each way into the confirmation should lead
  # out the way it came: from the suggestions back to the suggestions, from the counterparties list to the
  # survivor, which is what it always did.
  describe 'arriving from the suggestions' do
    around do |example|
      was = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = was
    end

    let!(:one) { counterparty("TESCO STORES 2228") }
    let!(:two) { counterparty("TESCO STORES 2889") }

    before do
      group = MergeSuggester::Group.new(name: "Tesco", counterparties: [ one, two ],
                                        reason: "Same shop.", categories: [ "Utilities" ])
      allow(MergeSuggester).to receive(:new)
        .and_return(instance_double(MergeSuggester, groups: [ group ], error: nil))
    end

    it 'comes back to the suggestions after merging, with that group gone' do
      visit merge_suggestions_path
      click_link 'Review'

      fill_in 'name', with: 'Tesco'
      click_button 'Merge'

      expect(page).to have_css('h1', text: 'Suggested merges')
      expect(page).to have_content('Nothing to suggest')
      expect(Counterparty.find_by(name: 'Tesco')).to be_present
    end

    it 'comes back to the suggestions on Cancel, having merged nothing' do
      visit merge_suggestions_path
      click_link 'Review'

      click_link 'Cancel'

      expect(page).to have_css('h1', text: 'Suggested merges')
      expect(Counterparty.where(id: [ one.id, two.id ]).count).to eq 2
    end

    # The other way in is unchanged: the survivor is the interesting thing when you ticked the boxes
    # yourself, and there is no suggestion list to go back to.
    it 'still lands on the survivor when the boxes were ticked on the list' do
      visit counterparties_path
      tick one
      tick two
      click_button 'Merge selected'

      fill_in 'name', with: 'Tesco'
      click_button 'Merge'

      expect(page).to have_css('h1', text: 'Tesco')
    end
  end
end
