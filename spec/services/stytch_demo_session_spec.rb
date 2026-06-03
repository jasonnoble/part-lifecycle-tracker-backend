require "rails_helper"

RSpec.describe StytchDemoSession do
  let(:magic_links) { instance_double(Stytch::MagicLinks) }
  let(:client) { instance_double(Stytch::Client, magic_links: magic_links) }
  subject(:minter) { described_class.new(client: client) }

  describe "#mint" do
    it "creates and authenticates an embedded magic link, returning the session pair" do
      user = build(:user, stytch_user_id: "user-test-quinn")
      allow(magic_links).to receive(:create)
        .with(user_id: "user-test-quinn")
        .and_return("token" => "embedded-ml-token")
      allow(magic_links).to receive(:authenticate)
        .with(token: "embedded-ml-token", session_duration_minutes: described_class::SESSION_DURATION_MINUTES)
        .and_return("session_jwt" => "demo.session.jwt", "session_token" => "demo-session-token")

      expect(minter.mint(user)).to eq(session_jwt: "demo.session.jwt", session_token: "demo-session-token")
    end

    it "raises NotLinkedError (without touching Stytch) when the user has no stytch_user_id" do
      user = build(:user, stytch_user_id: nil, email: "dr.quinn@example.com")
      expect(client).not_to receive(:magic_links)

      expect { minter.mint(user) }
        .to raise_error(described_class::NotLinkedError, /dr\.quinn@example\.com.*stytch:sync_users/)
    end

    it "fails loud (KeyError) when Stytch returns an error body instead of a token" do
      user = build(:user, stytch_user_id: "user-test-x")
      allow(magic_links).to receive(:create)
        .and_return("status_code" => 400, "error_type" => "user_not_found")

      expect { minter.mint(user) }.to raise_error(KeyError)
    end
  end

  describe ".mint" do
    it "delegates to a new instance with a lazily built client" do
      user = build(:user, stytch_user_id: "user-test-quinn")
      allow(StytchClient).to receive(:build).and_return(client)
      allow(magic_links).to receive(:create).and_return("token" => "t")
      allow(magic_links).to receive(:authenticate)
        .and_return("session_jwt" => "j", "session_token" => "s")

      expect(described_class.mint(user)).to eq(session_jwt: "j", session_token: "s")
    end
  end
end
