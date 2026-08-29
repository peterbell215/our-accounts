FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "member#{n}@example.com" }
    password { AuthenticationHelpers::SPEC_PASSWORD }

    # Scanned and proved: this one is asked for a code when they sign in.
    trait :with_totp do
      otp_secret { ROTP::Base32.random }
      otp_confirmed_at { Time.current }
    end

    # Offered a QR and never finished with it.  Deliberately still signs in on a password alone — being
    # locked out over a secret you never got as far as scanning is the one failure this must not have.
    trait :enrolling do
      otp_secret { ROTP::Base32.random }
    end
  end
end
