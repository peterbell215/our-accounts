require 'rails_helper'

RSpec.describe "Totp challenges", type: :request, signed_out: true do
  let(:user) { create(:user, :with_totp) }
  let(:code) { ROTP::TOTP.new(user.otp_secret).now }

  # The password step, and only that: it leaves the reader with a pending state and no Session row.
  def give_the_password
    post session_path, params: { email_address: user.email_address,
                                 password: AuthenticationHelpers::SPEC_PASSWORD }
  end

  describe "POST /totp_challenge" do
    it "signs the reader in when the code is right" do
      give_the_password

      expect { post totp_challenge_path, params: { otp_code: code } }
        .to change { user.sessions.count }.from(0).to(1)

      expect(response).to redirect_to(root_url)
    end

    it "creates nothing when the code is wrong" do
      give_the_password

      post totp_challenge_path, params: { otp_code: "000000" }

      expect(response).to redirect_to(new_totp_challenge_path)
      expect(Session.count).to be_zero
    end

    it "refuses a code that has already been used" do
      give_the_password
      post totp_challenge_path, params: { otp_code: code }
      delete session_path

      give_the_password
      post totp_challenge_path, params: { otp_code: code }

      expect(Session.count).to be_zero
    end
  end

  describe "arriving without having given the password" do
    it "sends a GET back to the beginning" do
      get new_totp_challenge_path

      expect(response).to redirect_to(new_session_path)
    end

    it "sends a POST back too, and signs nobody in" do
      user # so there is somebody a guessed code could belong to

      post totp_challenge_path, params: { otp_code: code }

      expect(response).to redirect_to(new_session_path)
      expect(Session.count).to be_zero
    end
  end

  describe "leaving it too long" do
    it "expires the pending state rather than holding it open" do
      give_the_password

      travel(TotpChallengesController::WINDOW + 1.minute) do
        post totp_challenge_path, params: { otp_code: ROTP::TOTP.new(user.otp_secret).now }

        expect(response).to redirect_to(new_session_path)
        expect(Session.count).to be_zero
      end
    end
  end
end
