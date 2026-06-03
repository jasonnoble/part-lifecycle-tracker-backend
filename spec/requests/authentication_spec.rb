require "rails_helper"

# Exercises the Authentication concern through a real endpoint (GET /me). The
# Stytch verification boundary is stubbed (see spec/support/authentication_helpers.rb);
# these specs assert the Rails-side behavior: 401 without a session, identity
# resolution to a seeded user, and the authenticated read-only / no-role path.
RSpec.describe "Authentication", type: :request do
  def json
    JSON.parse(response.body)
  end

  describe "without a valid Stytch session" do
    it "returns 401 when no session token is present" do
      sign_out

      get "/me"

      expect(response).to have_http_status(:unauthorized)
      expect(json).to include("code" => "UNAUTHENTICATED")
    end

    it "returns 401 when the session token is invalid or expired" do
      sign_out

      get "/me", headers: { "Authorization" => "Bearer expired.or.bogus" }

      expect(response).to have_http_status(:unauthorized)
      expect(json["code"]).to eq("UNAUTHENTICATED")
    end
  end

  describe "with a valid session for a seeded user" do
    it "resolves current_user and returns their assigned role" do
      user = create(:user, :qa_engineer, name: "Dr. Quinn", email: "dr.quinn@example.com")
      sign_in(user)

      get "/me", headers: { "Authorization" => "Bearer valid.session.jwt" }

      expect(response).to have_http_status(:ok)
      expect(json).to eq(
        "email" => "dr.quinn@example.com",
        "name" => "Dr. Quinn",
        "role" => "qa_engineer"
      )
    end
  end

  describe "with a valid session for an unseeded identity" do
    it "authenticates as read-only / no-role (null identity, not 401)" do
      sign_in_stytch_user("user-not-in-our-db")

      get "/me", headers: { "Authorization" => "Bearer valid.but.unknown" }

      expect(response).to have_http_status(:ok)
      expect(json).to eq("email" => nil, "name" => nil, "role" => nil)
    end
  end
end
