require "rails_helper"

# POST /demo-sessions — the SPA's one-click demo-login bootstrap (JAS-80).
# The Stytch minting boundary (StytchDemoSession) is stubbed, same style as the
# StytchAuthenticator stubs in authentication_spec.
RSpec.describe "Demo sessions", type: :request do
  def json
    JSON.parse(response.body)
  end

  describe "POST /demo-sessions" do
    it "mints a session for a seeded demo persona; the JWT then resolves them via /me" do
      user = create(:user, :qa_engineer, name: "Dr. Quinn", email: "dr.quinn@example.com",
                    stytch_user_id: "user-test-quinn")
      allow(StytchDemoSession).to receive(:mint).with(user)
        .and_return(session_jwt: "demo.session.jwt", session_token: "demo-session-token")

      post "/demo-sessions", params: { email: "dr.quinn@example.com" }, as: :json

      expect(response).to have_http_status(:created)
      expect(json).to eq("session_jwt" => "demo.session.jwt", "session_token" => "demo-session-token")

      # The acceptance round-trip: the minted JWT authenticates a follow-up /me.
      allow(StytchAuthenticator).to receive(:user_id_for).with("demo.session.jwt")
        .and_return(user.stytch_user_id)
      get "/me", headers: { "Authorization" => "Bearer demo.session.jwt" }
      expect(response).to have_http_status(:ok)
      expect(json).to include("email" => "dr.quinn@example.com", "name" => "Dr. Quinn", "role" => "qa_engineer")
    end

    it "is reachable without any session (it is the bootstrap)", openapi: false do
      create(:user, email: "jamie.torres@example.com", stytch_user_id: "user-test-jamie")
      allow(StytchDemoSession).to receive(:mint)
        .and_return(session_jwt: "j", session_token: "s")
      sign_out

      post "/demo-sessions", params: { email: "jamie.torres@example.com" }, as: :json

      expect(response).to have_http_status(:created)
    end

    it "returns 404 for a non-demo email without calling Stytch" do
      create(:user, email: "intruder@example.com") # seeded-looking but not a demo persona
      expect(StytchDemoSession).not_to receive(:mint)

      post "/demo-sessions", params: { email: "intruder@example.com" }, as: :json

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end

    it "returns 404 when the demo email is allowlisted but not seeded", openapi: false do
      expect(StytchDemoSession).not_to receive(:mint)

      post "/demo-sessions", params: { email: "sarah.chen@example.com" }, as: :json

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end

    it "fails loud with DEMO_USER_NOT_LINKED when the persona has no stytch_user_id", openapi: false do
      create(:user, email: "marcus.webb@example.com", stytch_user_id: nil)

      post "/demo-sessions", params: { email: "marcus.webb@example.com" }, as: :json

      expect(response).to have_http_status(:internal_server_error)
      expect(json["code"]).to eq("DEMO_USER_NOT_LINKED")
      expect(json["error"]).to include("stytch:sync_users")
    end
  end
end
