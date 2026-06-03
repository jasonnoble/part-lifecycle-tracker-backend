require "rails_helper"

RSpec.describe StytchClient do
  describe ".build" do
    it "builds a Stytch client from the stytch credentials" do
      allow(Rails.application.credentials).to receive(:stytch)
        .and_return(project_id: "project-test-1", secret: "secret-1", env: :test)
      fake = instance_double(Stytch::Client)
      expect(Stytch::Client).to receive(:new)
        .with(project_id: "project-test-1", secret: "secret-1", env: :test).and_return(fake)

      expect(described_class.build).to be(fake)
    end

    it "passes env: nil when unset (SDK infers live/test from the project_id)" do
      allow(Rails.application.credentials).to receive(:stytch)
        .and_return(project_id: "project-live-9", secret: "s")
      fake = instance_double(Stytch::Client)
      expect(Stytch::Client).to receive(:new)
        .with(project_id: "project-live-9", secret: "s", env: nil).and_return(fake)

      expect(described_class.build).to be(fake)
    end

    it "raises when stytch credentials are absent (fail loud, not a broken client)" do
      allow(Rails.application.credentials).to receive(:stytch).and_return(nil)

      expect { described_class.build }.to raise_error(KeyError)
    end
  end
end
