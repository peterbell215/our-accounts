require 'rails_helper'

# The way in, in a real browser.  `signed_out: true` turns off the hook in rails_helper that signs
# everything else in — these are the examples that have to do it themselves.
RSpec.describe 'Signing in', type: :system, signed_out: true do
  let(:password) { AuthenticationHelpers::SPEC_PASSWORD }

  def give_the_password(user, using: password)
    visit new_session_path
    fill_in 'Email address', with: user.email_address
    fill_in 'Password', with: using
    click_button 'Sign in'
  end

  it 'lets a reader with no second factor straight in' do
    user = create(:user)

    give_the_password user

    expect(page).to have_css('h1', text: 'Accounts')
    expect(page).to have_link('Sign out')
  end

  it 'says so, without saying which half was wrong, when the password is not right' do
    give_the_password create(:user), using: 'not the password'

    expect(page).to have_css('h1', text: 'Sign in')
    expect(page).to have_content('Try another email address or password')
  end

  it 'asks a reader with a second factor for a code, and does not let them past it' do
    user = create(:user, :with_totp)

    give_the_password user
    expect(page).to have_css('h1', text: 'Enter your code')

    # Abandoning the question is not a way round it.  This is the invariant in the browser: nothing is
    # signed in until the code has been given.
    visit categories_path
    expect(page).to have_css('h1', text: 'Sign in')
  end

  it 'lets them in once the code is right' do
    user = create(:user, :with_totp)

    give_the_password user
    fill_in 'Code', with: ROTP::TOTP.new(user.otp_secret).now
    click_button 'Confirm'

    expect(page).to have_css('h1', text: 'Accounts')
  end

  it 'asks again when the code is wrong, rather than letting them through' do
    give_the_password create(:user, :with_totp)

    fill_in 'Code', with: '000000'
    click_button 'Confirm'

    expect(page).to have_css('h1', text: 'Enter your code')
    expect(page).to have_content('That code was not right')
  end

  it 'does not ask a reader who started setting a factor up and never confirmed it' do
    give_the_password create(:user, :enrolling)

    expect(page).to have_css('h1', text: 'Accounts')
  end

  it 'returns the reader to the screen they were trying to reach' do
    user = create(:user)
    category = create(:category)

    visit category_path(category)
    expect(page).to have_css('h1', text: 'Sign in')

    fill_in 'Email address', with: user.email_address
    fill_in 'Password', with: password
    click_button 'Sign in'

    expect(page).to have_css('h1', text: category.name)
  end

  describe 'the menu bar' do
    # Every item on it would bounce straight back here, so there is nothing for it to do on this screen.
    it 'is not drawn while signed out' do
      visit new_session_path

      expect(page).to have_no_css('nav')
    end

    it 'carries the address and the way out once signed in' do
      user = create(:user)

      give_the_password user

      within('nav') do
        expect(page).to have_link(user.email_address, href: profile_path)
        expect(page).to have_link('Sign out')
      end
    end
  end

  describe 'signing out' do
    it 'returns to the sign-in screen and does not leave a way back in' do
      give_the_password create(:user)

      click_link 'Sign out'
      expect(page).to have_css('h1', text: 'Sign in')

      # What a reader pressing Back would do.
      visit categories_path
      expect(page).to have_css('h1', text: 'Sign in')
    end
  end
end
