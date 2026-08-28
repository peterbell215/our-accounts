# Turning the second factor on, and off again.
#
# `new` and `create` rather than `edit` and `update`, the habit CounterpartyMergesController explains:
# the GET shows what is about to happen and changes nothing, the POST is the thing that acts.
class TotpEnrolmentsController < ApplicationController
  before_action :set_user
  before_action :refuse_while_already_on, only: %i[ new create ]

  def new
    @user.begin_totp_enrolment!
  end

  def create
    # The secret is whatever `new` generated; this only ever fills one in for a POST that arrived without
    # one having been generated first, which is not a path a reader can take.
    @user.begin_totp_enrolment!

    if @user.confirm_totp_enrolment(params[:otp_code])
      redirect_to profile_path, notice: "Two-factor authentication is on. You will be asked for a code next time you sign in."
    else
      # Straight back to the same screen with the *same* secret and so the same QR.  Regenerating here
      # would be the natural-looking thing and quite wrong: the usual reason to be here is a mistyped code
      # or a phone whose clock has drifted, and a new secret would make the reader scan all over again to
      # fix neither.
      flash.now[:alert] = "That code was not right. Check the app is showing a code for #{User::ISSUER}, and try the next one."
      render :new, status: :unprocessable_content
    end
  end

  # Behind the current password, because otherwise anyone passing an unlocked browser takes the second
  # factor off in one click, and a second factor that can be removed without knowing the first is
  # decoration.
  def destroy
    unless @user.authenticate(params[:password])
      return redirect_to profile_path, alert: "That is not your password. Two-factor authentication is still on."
    end

    @user.disable_totp!
    redirect_to profile_path, status: :see_other,
                notice: "Two-factor authentication is off. Signing in now needs only your password."
  end

  private

  def set_user = @user = Current.user

  # Re-enrolling over a factor that is already live would leave the reader holding a QR they had not
  # confirmed and a phone entry that no longer worked, with no way to tell which was which.  Off, then on.
  def refuse_while_already_on
    return unless @user.totp_required?

    redirect_to profile_path,
                alert: "Two-factor authentication is already on. Turn it off first to set up a new app."
  end
end
