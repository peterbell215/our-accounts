require 'rails_helper'

# Signed out to begin with, these being the specs that are about getting in.
RSpec.describe "Sessions", type: :request, signed_out: true do
  let(:password) { AuthenticationHelpers::SPEC_PASSWORD }

  describe "POST /session" do
    it "signs in a user who has no second factor, in one step" do
      user = create(:user)

      post session_path, params: { email_address: user.email_address, password: password }

      expect(response).to redirect_to(root_url)
      expect(user.sessions.count).to eq(1)
    end

    it "takes the address however it was typed" do
      user = create(:user, email_address: "alice@example.com")

      post session_path, params: { email_address: "  Alice@Example.COM ", password: password }

      expect(user.sessions.count).to eq(1)
    end

    it "refuses a wrong password without creating anything" do
      user = create(:user)

      post session_path, params: { email_address: user.email_address, password: "wrong" }

      expect(response).to redirect_to(new_session_path)
      expect(Session.count).to be_zero
    end

    it "says nothing about whether the address exists" do
      create(:user, email_address: "alice@example.com")

      post session_path, params: { email_address: "alice@example.com", password: "wrong" }
      known = flash[:alert]

      post session_path, params: { email_address: "nobody@example.com", password: "wrong" }

      expect(flash[:alert]).to eq(known)
    end

    # The invariant the whole second factor rests on.  A Session row is what resume_session looks for, so
    # one written here would let anyone who abandoned the next screen straight in.
    it "creates no session for a user with a second factor, only a pending state" do
      user = create(:user, :with_totp)

      post session_path, params: { email_address: user.email_address, password: password }

      expect(response).to redirect_to(new_totp_challenge_path)
      expect(Session.count).to be_zero
    end

    it "returns the reader to the page that sent them here" do
      user = create(:user)
      category = create(:category)

      get category_path(category)
      expect(response).to redirect_to(new_session_path)

      post session_path, params: { email_address: user.email_address, password: password }

      expect(response).to redirect_to(category_url(category))
    end
  end

  describe "DELETE /session" do
    it "destroys the row and lets go of the cookie" do
      user = create(:user)
      sign_in_as(user)
      expect(user.sessions.count).to eq(1)

      delete session_path

      expect(response).to redirect_to(new_session_path)
      expect(user.sessions.count).to be_zero

      get categories_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "what is reachable while signed out" do
    it "does not include an ordinary screen" do
      get categories_path

      expect(response).to redirect_to(new_session_path)
    end

    # Rails::HealthController descends from ActionController::Base rather than from
    # ApplicationController, so it never sees the filter.  Asserted rather than assumed, because it is
    # exactly the sort of thing a later refactor of ApplicationController would quietly take away.
    it "does include the health check a load balancer needs" do
      get rails_health_check_path

      expect(response).to have_http_status(:ok)
    end

    # A fragment fetched by the transaction list cannot show a sign-in screen, and a redirect would be
    # followed by fetch and mistaken for an empty page of rows.  401 with the address in
    # WWW-Authenticate is what @rails/request.js already knows how to act on.
    it "answers a background fetch with 401 and where to go, not with a redirect" do
      account = create(:lloyds_account)

      get account_transactions_path(account, rows: 1), headers: { "X-Requested-With" => "XMLHttpRequest" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to eq(new_session_url)
    end
  end
end
