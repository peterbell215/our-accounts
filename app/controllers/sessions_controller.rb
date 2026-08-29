# The password step of signing in.
#
# It is only half the story where the reader has a second factor: on a correct password this writes two
# keys into the Rails session cookie and sends them to TotpChallengesController, which is the only other
# place a Session row is ever created.  The row is the thing that means "signed in", so writing one here
# would be a way past the code.
class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]

  # A no-op in test, where the cache store is :null_store, so nothing asserts on it.  Real in development
  # and production.
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_session_path, alert: "Too many attempts. Try again later." }

  def new
  end

  def create
    user = User.authenticate_by(params.permit(:email_address, :password))
    return redirect_to new_session_path, alert: "Try another email address or password." unless user

    # Against fixation: the cookie the reader arrives with must not be the cookie they leave signed in
    # with.  Where they were going is worth keeping across that, though — it is the whole reason they
    # were sent here in the first place.
    destination = session[:return_to_after_authenticating]
    reset_session
    session[:return_to_after_authenticating] = destination

    if user.totp_required?
      session[:pending_user_id] = user.id
      session[:pending_at] = Time.current.to_i
      redirect_to new_totp_challenge_path
    else
      start_new_session_for user
      redirect_to after_authentication_url
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other, notice: "Signed out."
  end
end
