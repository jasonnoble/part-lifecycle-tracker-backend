require "rails_helper"

# Unit-tests the real verification logic with the Stytch SDK client stubbed, so
# no network/JWKS work happens. Request specs stub StytchAuthenticator itself;
# this spec covers the code that talks to the SDK.
RSpec.describe StytchAuthenticator do
  subject(:authenticator) { described_class.new }

  describe "#user_id_for" do
    let(:sessions) { instance_double(Stytch::Sessions) }
    let(:client) { instance_double(Stytch::Client, sessions: sessions) }

    before { allow(authenticator).to receive(:client).and_return(client) }

    it "returns the user_id from a verified session" do
      allow(sessions).to receive(:authenticate_jwt)
        .with("good.jwt", max_token_age_seconds: described_class::MAX_TOKEN_AGE_SECONDS)
        .and_return("session" => { "user_id" => "user-live-abc123" })

      expect(authenticator.user_id_for("good.jwt")).to eq("user-live-abc123")
    end

    it "returns nil for a blank token without calling Stytch" do
      expect(sessions).not_to receive(:authenticate_jwt)

      expect(authenticator.user_id_for("")).to be_nil
      expect(authenticator.user_id_for(nil)).to be_nil
    end

    it "returns nil when verification raises a Stytch JWT error" do
      allow(sessions).to receive(:authenticate_jwt)
        .and_raise(Stytch::JWTExpiredSignatureError)

      expect(authenticator.user_id_for("expired.jwt")).to be_nil
    end

    it "returns nil when the response carries no user_id (e.g. API rejection)" do
      allow(sessions).to receive(:authenticate_jwt)
        .and_return("status_code" => 401, "error_type" => "session_not_found")

      expect(authenticator.user_id_for("rejected.jwt")).to be_nil
    end

    describe ".user_id_for" do
      it "delegates to a new instance" do
        allow(sessions).to receive(:authenticate_jwt).and_return("session" => { "user_id" => "u1" })
        allow(described_class).to receive(:new).and_return(authenticator)

        expect(described_class.user_id_for("jwt")).to eq("u1")
      end
    end
  end

  describe "#client" do
    it "memoizes the client built by StytchClient" do
      fake_client = instance_double(Stytch::Client)
      allow(StytchClient).to receive(:build).and_return(fake_client)

      expect(authenticator.send(:client)).to be(fake_client)
      authenticator.send(:client)
      expect(StytchClient).to have_received(:build).once # memoized
    end
  end
end
