# Changing your own password.  This is the whole of password recovery inside the application: there is
# no reset-by-email, because there is no SMTP anywhere, and a forgotten password is
# `bin/rails users:change_password` from the machine the database is on.
class PasswordChangesController < ApplicationController
  def new
  end

  def create
    user = Current.user

    unless user.authenticate(params[:current_password])
      flash.now[:alert] = "That is not your current password."
      return render :new, status: :unprocessable_content
    end

    user.password = params[:password]
    user.password_confirmation = params[:password_confirmation]

    unless user.save
      flash.now[:alert] = user.errors.full_messages.to_sentence
      return render :new, status: :unprocessable_content
    end

    # The point of a new password is that the old one stops working everywhere, not merely here.  A
    # change that leaves the other devices signed in has not done what the reader thought it did, so it
    # is done and then said out loud.
    signed_out = user.sessions.where.not(id: Current.session.id).destroy_all.count

    redirect_to profile_path, notice: [
      "Your password has been changed.",
      ("Signed out #{helpers.pluralize(signed_out, 'other device')}." if signed_out.positive?)
    ].compact.join(" ")
  end
end
