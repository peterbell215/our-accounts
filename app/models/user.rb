# Someone who can sign in.  Several people share one set of accounts and transactions — there is no
# scoping and no ownership anywhere in the schema — so this record exists to answer "may you in", and
# nothing more.
class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  # The secret is ciphertext in the column.  A password digest is bcrypt and survives being copied; a
  # TOTP secret in plain text *is* the second factor, and anyone holding a copy of the database file
  # could mint valid codes for ever with nothing on screen ever saying so.  Non-deterministic, because
  # nothing ever looks a user up by it.
  encrypts :otp_secret

  # What the authenticator app files the entry under.
  ISSUER = "our-accounts".freeze

  # How far either side of now a code is still accepted, for a phone whose clock has drifted.  Half a
  # step: wide enough for the clocks that are actually wrong, narrow enough that a code is not good for
  # appreciably longer than the thirty seconds it is shown for.
  DRIFT = 15

  validates :email_address, presence: true, uniqueness: { case_sensitive: false }
  # allow_nil, so that saving a user for any other reason is not an occasion to retype the password.
  validates :password, length: { minimum: 12 }, allow_nil: true

  # The only question the sign-in path asks.  A secret that has been generated but never proved does not
  # count: the reader may have closed the enrolment screen without ever scanning the QR, and locking them
  # out over a secret they do not have is the one failure this feature must not have.
  def totp_required? = otp_confirmed_at.present?

  # Scanned, or at least offered, but not yet proved.  Named on the profile screen so that a half-finished
  # enrolment is something the reader can see rather than a silent nothing.
  def enrolling? = otp_secret.present? && otp_confirmed_at.nil?

  # Generates the secret on the first visit to the enrolment screen and keeps it thereafter.  Reloading
  # that screen has to show the *same* QR: a new secret each time would invalidate the one already open
  # on the phone, and the reader would never be able to finish.
  def begin_totp_enrolment!
    update!(otp_secret: ROTP::Base32.random) if otp_secret.blank?
    otp_secret
  end

  # What the QR encodes.
  def provisioning_uri = totp.provisioning_uri(email_address)

  # True when the code is right and has not been used before.
  #
  # `after:` is what stops a code being used twice.  Without it a code read over a shoulder, or off a
  # proxy log, is good for the rest of its thirty-second window on somebody else's device.  ROTP hands
  # back the timestamp of the step that matched, which is exactly what the next call has to exclude.
  def verify_otp(code)
    return false if otp_secret.blank? || code.blank?

    matched_at = totp.verify(code.to_s.strip, drift_behind: DRIFT, drift_ahead: DRIFT,
                             after: otp_last_used_at)
    return false unless matched_at

    update!(otp_last_used_at: Time.at(matched_at))
    true
  end

  # Turning it on: the reader proves they can produce a code before the second factor starts being asked
  # for.  Confirming with a code rather than on trust is the whole point — a QR that was never scanned
  # correctly would otherwise lock the account on the next sign-in.
  def confirm_totp_enrolment(code)
    return false unless verify_otp(code)

    update!(otp_confirmed_at: Time.current)
    true
  end

  # Turning it off, from the profile screen or from `bin/rails users:disable_totp`.  All three columns go:
  # a secret left behind would be re-offered as though it were still the one on the reader's phone.
  def disable_totp!
    update!(otp_secret: nil, otp_confirmed_at: nil, otp_last_used_at: nil)
  end

  private

  def totp = ROTP::TOTP.new(otp_secret, issuer: ISSUER)
end
