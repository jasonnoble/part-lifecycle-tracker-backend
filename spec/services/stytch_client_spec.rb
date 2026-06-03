require "rails_helper"

RSpec.describe StytchClient do
  # Set ENV vars for the duration of a block, restoring prior values after.
  def with_env(vars)
    previous = vars.keys.index_with { |key| ENV[key] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

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

    it "prefers STYTCH_PROJECT_ID/STYTCH_SECRET from ENV over credentials" do
      allow(Rails.application.credentials).to receive(:stytch)
        .and_return(project_id: "from-credentials", secret: "from-credentials")
      fake = instance_double(Stytch::Client)
      expect(Stytch::Client).to receive(:new)
        .with(project_id: "project-live-env", secret: "env-secret", env: nil).and_return(fake)

      with_env("STYTCH_PROJECT_ID" => "project-live-env", "STYTCH_SECRET" => "env-secret") do
        expect(described_class.build).to be(fake)
      end
    end

    it "passes STYTCH_ENV through when set alongside the ENV pair" do
      fake = instance_double(Stytch::Client)
      expect(Stytch::Client).to receive(:new)
        .with(project_id: "project-test-env", secret: "env-secret", env: "test").and_return(fake)

      env = { "STYTCH_PROJECT_ID" => "project-test-env", "STYTCH_SECRET" => "env-secret", "STYTCH_ENV" => "test" }
      with_env(env) do
        expect(described_class.build).to be(fake)
      end
    end

    it "falls back to credentials when only one of the ENV pair is set" do
      allow(Rails.application.credentials).to receive(:stytch)
        .and_return(project_id: "from-credentials", secret: "credentials-secret")
      fake = instance_double(Stytch::Client)
      expect(Stytch::Client).to receive(:new)
        .with(project_id: "from-credentials", secret: "credentials-secret", env: nil).and_return(fake)

      with_env("STYTCH_PROJECT_ID" => "project-live-env", "STYTCH_SECRET" => nil) do
        expect(described_class.build).to be(fake)
      end
    end
  end
end
