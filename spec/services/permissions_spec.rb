require "rails_helper"

RSpec.describe Permissions do
  describe ".can?" do
    it "grants step.install and step.validate only to installers" do
      expect(described_class.can?(build(:user, :installer), "step.install")).to be true
      expect(described_class.can?(build(:user, :installer), "step.validate")).to be true

      %i[salesperson floor_manager qa_engineer site_manager].each do |role|
        user = build(:user, role)
        expect(described_class.can?(user, "step.install")).to be false
        expect(described_class.can?(user, "step.validate")).to be false
      end
    end

    it "grants step.certify and instance.record_test only to qa_engineer" do
      expect(described_class.can?(build(:user, :qa_engineer), "step.certify")).to be true
      expect(described_class.can?(build(:user, :qa_engineer), "instance.record_test")).to be true

      %i[salesperson floor_manager installer site_manager].each do |role|
        user = build(:user, role)
        expect(described_class.can?(user, "step.certify")).to be false
        expect(described_class.can?(user, "instance.record_test")).to be false
      end
    end

    it "grants instance.record_event to every assigned role" do
      User.roles.keys.each do |role|
        expect(described_class.can?(build(:user, role: role), "instance.record_event")).to be true
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
    it "gives installers the assembly abilities" do
      expect(described_class.for(build(:user, :installer))).to contain_exactly(
        "step.install", "step.validate", "instance.record_event"
      )
    end

    it "gives qa_engineer the sign-off abilities" do
      expect(described_class.for(build(:user, :qa_engineer))).to contain_exactly(
        "step.certify", "instance.record_event", "instance.record_test"
      )
    end

    it "gives non-assembly roles only event recording" do
      expect(described_class.for(build(:user, :salesperson))).to contain_exactly("instance.record_event")
    end

    it "is empty for a read-only (nil) user" do
      expect(described_class.for(nil)).to eq([])
    end
  end
end
