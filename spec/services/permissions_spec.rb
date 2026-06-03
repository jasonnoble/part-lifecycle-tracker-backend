require "rails_helper"

RSpec.describe Permissions do
  describe ".can?" do
    it "grants step.certify only to qa_engineer" do
      expect(described_class.can?(build(:user, :qa_engineer), "step.certify")).to be true
      expect(described_class.can?(build(:user, :installer), "step.certify")).to be false
      expect(described_class.can?(build(:user, :site_manager), "step.certify")).to be false
    end

    it "grants install/validate/record abilities to every assigned role" do
      User.roles.keys.each do |role|
        user = build(:user, role: role)
        expect(described_class.can?(user, "step.install")).to be true
        expect(described_class.can?(user, "step.validate")).to be true
        expect(described_class.can?(user, "instance.record_event")).to be true
        expect(described_class.can?(user, "instance.record_test")).to be true
      end
    end

    it "denies everything to a read-only (nil) user" do
      expect(described_class.can?(nil, "step.install")).to be false
      expect(described_class.can?(nil, "step.certify")).to be false
    end

    it "raises on an unknown ability (fail loud on typos)" do
      expect { described_class.can?(build(:user), "step.frobnicate") }.to raise_error(KeyError)
    end
  end

  describe ".for" do
    it "returns the full ability list for qa_engineer" do
      expect(described_class.for(build(:user, :qa_engineer))).to contain_exactly(
        "step.install", "step.validate", "step.certify",
        "instance.record_event", "instance.record_test"
      )
    end

    it "excludes step.certify for an installer" do
      abilities = described_class.for(build(:user, :installer))
      expect(abilities).to include("step.install", "step.validate")
      expect(abilities).not_to include("step.certify")
    end

    it "is empty for a read-only (nil) user" do
      expect(described_class.for(nil)).to eq([])
    end
  end
end
