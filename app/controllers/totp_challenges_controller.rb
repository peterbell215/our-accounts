# The code step of signing in, for a reader whose second factor is on.
#
# Its own controller rather than another action on SessionsController, the same habit as
# CounterpartyMergesController: the operation is the noun.  It is also the only place other than the
# password step that creates a Session row, and keeping that in one small file is what makes the
# invariant behind the second factor easy to check — a row exists only for a fully authenticated
# sign-in, so nothing before this point can be mistaken for being signed in.
class TotpChallengesController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  before_action :require_pending_user

  # Long enough to fetch a phone from another room, short enough that a half-authenticated cookie left
  # on a shared machine is worth nothing to whoever sits down next.
  WINDOW = 5.minutes

  # Counted per account rather than per address, unlike the password step: guessing a six-digit code is
  # an attack on one person, and whoever is doing it is not obliged to stay on one address.
  rate_limit to: 10, within: 3.minutes, only: :create,
             by: -> { session[:pending_user_id] || request.remote_ip },
             with: -> { redirect_to new_session_path, alert: "Too many attempts. Try again later." }

  def new
  end

  def create
    unless @pending_user.verify_otp(params[:otp_code])
      return redirect_to new_totp_challenge_path, alert: "That code was not right. Try the next one."
    end

    session.delete(:pending_user_id)
    session.delete(:pending_at)

    start_new_session_for @pending_user
    redirect_to after_authentication_url
  end

  private

  # Nothing here works without the password step having just happened.  Arriving with no pending state —
  # by bookmark, by back button, or by hopeful guess — is not an error to explain, it is simply the
  # beginning of signing in.
  def require_pending_user
    @pending_user = User.find_by(id: session[:pending_user_id]) if pending_in_time?

    return if @pending_user

    session.delete(:pending_user_id)
    session.delete(:pending_at)
    redirect_to new_session_path, alert: "That took too long. Please sign in again."
  end

  def pending_in_time?
    started_at = session[:pending_at]
    started_at.present? && Time.at(started_at) > WINDOW.ago
  end
end
