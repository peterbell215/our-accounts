require 'rails_helper'

RSpec.describe User do
  describe 'the email address' do
    it 'is squished and lowercased, so that it matches itself however it was typed' do
      user = create(:user, email_address: "  Alice@Example.COM ")

      expect(user.email_address).to eq("alice@example.com")
    end

    it 'is refused where another user already has it' do
      create(:user, email_address: "alice@example.com")
      duplicate = build(:user, email_address: "ALICE@example.com")

      expect(duplicate).not_to be_valid
    end
  end

  describe 'the password' do
    let!(:user) { create(:user, email_address: "alice@example.com") }

    it 'signs the user in when it is right' do
      found = User.authenticate_by(email_address: "alice@example.com",
                                   password: AuthenticationHelpers::SPEC_PASSWORD)

      expect(found).to eq(user)
    end

    it 'does not when it is wrong' do
      found = User.authenticate_by(email_address: "alice@example.com", password: "not the password")

      expect(found).to be_nil
    end

    it 'has to be long enough to be worth having' do
      expect(build(:user, password: "short")).not_to be_valid
    end
  end

  describe 'the second factor' do
    it 'is not asked for until it has been confirmed' do
      # The one failure this must not have: a reader who opened the enrolment screen, never scanned the
      # QR, and closed it again has a secret on their row and no way to produce a code for it.
      expect(create(:user, :enrolling)).not_to be_totp_required
      expect(create(:user, :enrolling)).to be_enrolling
    end

    it 'is asked for once it has been' do
      expect(create(:user, :with_totp)).to be_totp_required
    end

    it 'accepts the code the app is currently showing' do
      user = create(:user, :with_totp)

      expect(user.verify_otp(ROTP::TOTP.new(user.otp_secret).now)).to be true
    end

    it 'refuses a code that is not the one' do
      user = create(:user, :with_totp)

      expect(user.verify_otp("000000")).to be false
    end

    it 'refuses the same code a second time' do
      # Without this, a code read over a shoulder or off a proxy log is good for the rest of its thirty
      # seconds on somebody else's device.
      user = create(:user, :with_totp)
      code = ROTP::TOTP.new(user.otp_secret).now

      expect(user.verify_otp(code)).to be true
      expect(user.verify_otp(code)).to be false
    end

    it 'is confirmed by producing a code, not on trust' do
      user = create(:user, :enrolling)

      expect(user.confirm_totp_enrolment("000000")).to be false
      expect(user.reload.otp_confirmed_at).to be_nil

      expect(user.confirm_totp_enrolment(ROTP::TOTP.new(user.otp_secret).now)).to be true
      expect(user.reload.otp_confirmed_at).to be_present
    end

    it 'is forgotten entirely when it is turned off' do
      user = create(:user, :with_totp)
      user.verify_otp(ROTP::TOTP.new(user.otp_secret).now)

      user.disable_totp!

      expect(user.reload).to have_attributes(otp_secret: nil, otp_confirmed_at: nil,
                                             otp_last_used_at: nil)
    end

    # The reason config/environments/test.rb spells out encryption keys of its own, and the reason this
    # example is worth its weight: a bcrypt digest survives being copied, and a TOTP secret in plain text
    # *is* the second factor to whoever has the file.
    it 'is not readable as plain text in the row' do
      user = create(:user, :with_totp)

      stored = User.lease_connection.select_value("SELECT otp_secret FROM users WHERE id = #{user.id}")

      expect(stored).to be_present
      expect(stored).not_to eq(user.otp_secret)
      expect(stored).not_to include(user.otp_secret)
    end
  end

  it 'takes its sessions with it when it goes' do
    user = create(:user)
    user.sessions.create!

    expect { user.destroy }.to change(Session, :count).by(-1)
  end
end
