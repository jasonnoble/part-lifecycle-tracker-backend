require "rails_helper"

RSpec.describe WorkOrderStepSerializer do
  let(:homer) { create(:part_definition, part_number: "WOS-HOMER-001", name: "The Homer") }
  let(:muzzle) { create(:part_definition, part_number: "WOS-MUZZLE-001", name: "Muzzle") }
  let(:bom_item) { create(:bom_item, parent: homer, child: muzzle, quantity: 1) }
  let(:work_order) do
    create(:work_order, part_definition: homer,
                        part_instance: create(:part_instance, part_definition: homer, serial_number: "WOS-SN-1"))
  end

  def serialize(step)
    JSON.parse(described_class.new(step).serialize)
  end

  # Covers the nil branch of the &. timestamp guards.
  it "renders nil lifecycle timestamps for a PENDING step" do
    step = create(:work_order_step, work_order: work_order, bom_item: bom_item, status: "PENDING")

    json = serialize(step)

    expect(json["installedAt"]).to be_nil
    expect(json["validatedAt"]).to be_nil
    expect(json["certifiedAt"]).to be_nil
  end

  # Covers the present branch: each timestamp rendered as UTC ISO8601(3).
  it "renders UTC ISO8601(3) lifecycle timestamps for a CERTIFIED step" do
    at = Time.utc(2026, 5, 31, 12, 0, 0)
    step = create(:work_order_step, work_order: work_order, bom_item: bom_item, status: "CERTIFIED",
                                    installed_at: at, validated_at: at, certified_at: at,
                                    installed_actor: "installer@factory.com",
                                    validated_actor: "validator@factory.com",
                                    certified_actor: "certifier@factory.com")

    json = serialize(step)

    expect(json["installedAt"]).to eq("2026-05-31T12:00:00.000Z")
    expect(json["validatedAt"]).to eq("2026-05-31T12:00:00.000Z")
    expect(json["certifiedAt"]).to eq("2026-05-31T12:00:00.000Z")
  end
end
