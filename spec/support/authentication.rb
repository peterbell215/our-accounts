# Signing in, for the specs of everything that now sits behind a sign-in.
#
# A plain module and nothing else.  spec/rails_helper.rb requires this directory *before* it requires
# rspec/rails, so nothing here may touch RSpec::Rails or Capybara at load time — the same reason
# AccountTrxDataGenerator beside it is a plain class.  The hooks that use these live in rails_helper.rb.
module AuthenticationHelpers
  # One password for the whole suite.  Long enough to pass the model's own minimum, which is the only
  # thing that makes its length interesting.
  SPEC_PASSWORD = "correct horse battery staple".freeze

  # Whoever the hooks in rails_helper.rb signed in for this example.  Current.user is no use for that:
  # CurrentAttributes is reset at the end of every request, so by the time an example looks it is nil.
  attr_reader :signed_in_user

  # For request specs: straight at the controller, because a request spec is not pretending to be a
  # browser and the sign-in path has its own spec.
  def sign_in_as(user)
    @signed_in_user = user

    post session_path, params: { email_address: user.email_address, password: SPEC_PASSWORD }
    post totp_challenge_path, params: { otp_code: current_totp(user) } if user.totp_required?
  end

  # For system specs: through the screens, as a person would.  Two page loads, which is what the sign-in
  # gate costs the suite, and in exchange every system example exercises the real path in.
  def sign_in_through_the_form(user)
    @signed_in_user = user

    visit new_session_path
    fill_in "Email address", with: user.email_address
    fill_in "Password", with: SPEC_PASSWORD
    click_button "Sign in"

    # Waiting here is not belt and braces.  click_button does not wait for the page it asks for, so
    # without something to synchronise on, the example's own first `visit` cancels the sign-in in flight
    # and the browser arrives holding no cookie at all.  That fails intermittently, and it fails in the
    # example rather than here — a Show screen that is somehow the sign-in screen, every third run.
    expect(page).to have_no_button("Sign in")

    return unless user.totp_required?

    fill_in "Code", with: current_totp(user)
    click_button "Confirm"
    expect(page).to have_no_button("Confirm")
  end

  # The code the reader's phone would be showing.
  def current_totp(user) = ROTP::TOTP.new(user.otp_secret).now
end
