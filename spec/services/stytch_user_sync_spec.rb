require "rails_helper"

RSpec.describe StytchUserSync do
  let(:users_api) { instance_double(Stytch::Users) }
  let(:client) { instance_double(Stytch::Client, users: users_api) }
  subject(:sync) { described_class.new(client: client) }

  def search_returning(user_id)
    results = user_id ? [ { "user_id" => user_id } ] : []
    allow(users_api).to receive(:search).and_return("results" => results)
  end

  describe "#call" do
    it "is a no-op when the user is already linked" do
      user = create(:user, stytch_user_id: "user-existing")
      expect(client).not_to receive(:users)

      expect { sync.call(user) }.not_to(change { user.reload.stytch_user_id })
    end

    it "links to an existing Stytch user found by email" do
      user = create(:user, stytch_user_id: nil, email: "dr.quinn@example.com")
      search_returning("user-found")
      expect(users_api).not_to receive(:create)

      sync.call(user)

      expect(user.reload.stytch_user_id).to eq("user-found")
    end

    it "creates a Stytch user when none exists and stores the id" do
      user = create(:user, stytch_user_id: nil, email: "new@example.com")
      search_returning(nil)
      expect(users_api).to receive(:create)
        .with(email: "new@example.com").and_return("user_id" => "user-created")

      sync.call(user)

      expect(user.reload.stytch_user_id).to eq("user-created")
    end

    it "leaves the user unlinked when creation returns no id" do
      user = create(:user, stytch_user_id: nil)
      search_returning(nil)
      allow(users_api).to receive(:create).and_return("status_code" => 400, "error_type" => "duplicate_email")

      sync.call(user)

      expect(user.reload.stytch_user_id).to be_nil
    end
  end

  describe ".call" do
    it "delegates to a new instance using a built client" do
      user = create(:user, stytch_user_id: "already-linked")
      allow(StytchClient).to receive(:build).and_return(client)

      expect(described_class.call(user)).to eq(user)
      expect(StytchClient).to have_received(:build)
    end
  end
end
