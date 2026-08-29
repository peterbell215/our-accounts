require 'rails_helper'

RSpec.describe "Password changes", type: :request do
  let(:user) { signed_in_user }
  let(:current) { AuthenticationHelpers::SPEC_PASSWORD }
  let(:replacement) { "a whole new password entirely" }

  def change_to(new_password, current_password: current)
    post password_change_path, params: { current_password: current_password,
                                         password: new_password,
                                         password_confirmation: new_password }
  end

  it "changes the password when the current one is given" do
    change_to replacement

    expect(response).to redirect_to(profile_path)
    expect(User.authenticate_by(email_address: user.email_address, password: replacement)).to eq(user)
    expect(User.authenticate_by(email_address: user.email_address, password: current)).to be_nil
  end

  it "refuses without the current one" do
    change_to replacement, current_password: "not the password"

    expect(response).to have_http_status(:unprocessable_content)
    expect(User.authenticate_by(email_address: user.email_address, password: current)).to eq(user)
  end

  it "refuses a replacement the model would not accept" do
    change_to "short"

    expect(response).to have_http_status(:unprocessable_content)
    expect(User.authenticate_by(email_address: user.email_address, password: current)).to eq(user)
  end

  it "refuses a replacement typed differently the second time" do
    post password_change_path, params: { current_password: current, password: replacement,
                                         password_confirmation: "something else" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(User.authenticate_by(email_address: user.email_address, password: current)).to eq(user)
  end

  describe "the other devices" do
    # The point of a new password is that the old one stops working everywhere.  The device doing the
    # changing is the exception: signing the reader out of the screen they are standing at would be a
    # strange way to tell them it worked.
    it "are signed out, and this one is not" do
      elsewhere = user.sessions.create!
      here = user.sessions.order(:created_at).first

      change_to replacement

      expect(Session.exists?(elsewhere.id)).to be false
      expect(Session.exists?(here.id)).to be true
    end
  end
end
