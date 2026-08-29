require 'rails_helper'

# Signed in throughout, by the hook in rails_helper — enrolment is something you do to your own login,
# so there is no version of these that happens signed out.
RSpec.describe "Totp enrolments", type: :request do
  let(:user) { signed_in_user }

  describe "GET /totp_enrolment/new" do
    it "draws the QR on the page rather than fetching it from anywhere" do
      get new_totp_enrolment_path

      expect(response.body).to include("<svg")
      expect(response.body).to include(user.reload.otp_secret)
    end

    it "keeps the same secret when the screen is reloaded, so a scanned QR stays good" do
      get new_totp_enrolment_path
      first = user.reload.otp_secret

      get new_totp_enrolment_path

      expect(user.reload.otp_secret).to eq(first)
    end

    it "refuses to start again over a factor that is already on" do
      get new_totp_enrolment_path
      post totp_enrolment_path, params: { otp_code: ROTP::TOTP.new(user.reload.otp_secret).now }

      get new_totp_enrolment_path

      expect(response).to redirect_to(profile_path)
    end
  end

  describe "POST /totp_enrolment" do
    before { get new_totp_enrolment_path }

    it "turns the factor on when the code proves the app is set up" do
      post totp_enrolment_path, params: { otp_code: ROTP::TOTP.new(user.reload.otp_secret).now }

      expect(response).to redirect_to(profile_path)
      expect(user.reload).to be_totp_required
    end

    it "leaves it off, and the secret alone, when the code is wrong" do
      secret = user.reload.otp_secret

      post totp_enrolment_path, params: { otp_code: "000000" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload).not_to be_totp_required
      expect(user.reload.otp_secret).to eq(secret)
    end
  end

  describe "DELETE /totp_enrolment" do
    before do
      get new_totp_enrolment_path
      post totp_enrolment_path, params: { otp_code: ROTP::TOTP.new(user.reload.otp_secret).now }
    end

    it "turns the factor off for the right password" do
      delete totp_enrolment_path, params: { password: AuthenticationHelpers::SPEC_PASSWORD }

      expect(user.reload).not_to be_totp_required
      expect(user.reload.otp_secret).to be_nil
    end

    # Otherwise anyone passing an unlocked browser takes the second factor off in one click.
    it "changes nothing for the wrong one" do
      delete totp_enrolment_path, params: { password: "not the password" }

      expect(response).to redirect_to(profile_path)
      expect(user.reload).to be_totp_required
    end
  end
end
