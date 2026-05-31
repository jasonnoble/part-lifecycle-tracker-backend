require "rails_helper"

# The canonical integration test (JAS-38): muzzle-before-dome dependency
# enforcement, end to end over the real Track 6 endpoints. This is the v0 demo
# scenario and must pass before ship.
#
# Tagged `openapi: false` for the whole file: these are flow assertions over
# endpoints already documented by their own request specs, so they must add
# NOTHING to doc/openapi.yaml.
RSpec.describe "Muzzle before dome (dependency enforcement)", type: :request, openapi: false do
  def json
    JSON.parse(response.body)
  end

  # --- The Homer definition + BOM with the MUZZLE -> DOME dependency ---
  let(:homer) { create(:part_definition, part_number: "THE-HOMER-001", name: "The Homer", status: "RELEASED") }
  let(:muzzle) { create(:part_definition, part_number: "MUZZLE-001", name: "Muzzle", status: "RELEASED") }
  let(:dome) { create(:part_definition, part_number: "DOME-TRANS-001", name: "Transparent Dome", status: "RELEASED") }

  let!(:muzzle_bom) { create(:bom_item, parent: homer, child: muzzle, quantity: 1) }
  let!(:dome_bom) { create(:bom_item, parent: homer, child: dome, quantity: 1) }

  # The canonical rule: the muzzle must be installed and certified before the dome.
  let!(:dependency) { create(:bom_item_dependency, prerequisite: muzzle_bom, dependent: dome_bom) }

  # The assembly instance the work order is opened against, plus the serialized
  # components installed into each step.
  let!(:assembly) { create(:part_instance, part_definition: homer, serial_number: "HMR-0047", current_status: "IN_ASSEMBLY") }
  let!(:muzzle_component) { create(:part_instance, part_definition: muzzle, serial_number: "MZL-0001", current_status: "RECEIVED") }
  let!(:dome_component) { create(:part_instance, part_definition: dome, serial_number: "DOME-0001", current_status: "RECEIVED") }

  let(:tech_one) { "jamie@factory.com" }
  let(:tech_two) { "riley@factory.com" }
  let(:qa) { "quinn@factory.com" }

  def step_for(child_part_number)
    json["steps"].find { |s| s["childPartNumber"] == child_part_number }
  end

  it "enforces muzzle-before-dome end to end: blocks the dome first, then completes in order" do
    # 1. Open a work order for the Homer -> one PENDING step per BOM item.
    post "/work-orders", params: { partNumber: "THE-HOMER-001", serialNumber: "HMR-0047" }, as: :json
    expect(response).to have_http_status(:created)
    expect(json["status"]).to eq("OPEN")
    expect(json["steps"].map { |s| s["status"] }).to all(eq("PENDING"))

    work_order_id = json["id"]
    muzzle_step_id = step_for("MUZZLE-001").fetch("id")
    dome_step_id = step_for("DOME-TRANS-001").fetch("id")

    # 2. Attempt to install the DOME first -> 409 DEPENDENCY_NOT_MET naming MUZZLE-001.
    post "/work-orders/#{work_order_id}/steps/#{dome_step_id}/install",
      params: { installedSerial: "DOME-0001", actor: tech_one }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(json["code"]).to eq("DEPENDENCY_NOT_MET")
    expect(json["error"]).to include("MUZZLE-001")

    # 3. Install the muzzle (Tech 1). Appends an INSTALLED lifecycle event.
    expect {
      post "/work-orders/#{work_order_id}/steps/#{muzzle_step_id}/install",
        params: { installedSerial: "MZL-0001", actor: tech_one }, as: :json
    }.to change { muzzle_component.lifecycle_events.where(event_type: "INSTALLED").count }.by(1)
    expect(response).to have_http_status(:ok)
    expect(step_for("MUZZLE-001")["status"]).to eq("INSTALLED")
    expect(muzzle_component.reload.current_status).to eq("INSTALLED")

    # 4-eyes rejection: the installer cannot also validate -> 409 SAME_ACTOR.
    post "/work-orders/#{work_order_id}/steps/#{muzzle_step_id}/validate",
      params: { actor: tech_one }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(json["code"]).to eq("SAME_ACTOR")

    # 4. Validate the muzzle (Tech 2), then certify (QA).
    post "/work-orders/#{work_order_id}/steps/#{muzzle_step_id}/validate",
      params: { actor: tech_two }, as: :json
    expect(response).to have_http_status(:ok)
    expect(step_for("MUZZLE-001")["status"]).to eq("VALIDATED")

    post "/work-orders/#{work_order_id}/steps/#{muzzle_step_id}/certify",
      params: { actor: qa }, as: :json
    expect(response).to have_http_status(:ok)
    expect(step_for("MUZZLE-001")["status"]).to eq("CERTIFIED")

    # 5. Now the dome installs successfully (prerequisite is CERTIFIED).
    post "/work-orders/#{work_order_id}/steps/#{dome_step_id}/install",
      params: { installedSerial: "DOME-0001", actor: tech_one }, as: :json
    expect(response).to have_http_status(:ok)
    expect(step_for("DOME-TRANS-001")["status"]).to eq("INSTALLED")
    expect(dome_component.reload.current_status).to eq("INSTALLED")

    # Validate (different actor) and certify the dome.
    post "/work-orders/#{work_order_id}/steps/#{dome_step_id}/validate",
      params: { actor: tech_two }, as: :json
    expect(response).to have_http_status(:ok)

    post "/work-orders/#{work_order_id}/steps/#{dome_step_id}/certify",
      params: { actor: qa }, as: :json
    expect(response).to have_http_status(:ok)
    expect(step_for("DOME-TRANS-001")["status"]).to eq("CERTIFIED")

    # 6. Complete the work order -> 200, COMPLETE, CERTIFIED event on the assembly.
    expect {
      post "/work-orders/#{work_order_id}/complete", as: :json
    }.to change { assembly.lifecycle_events.where(event_type: "CERTIFIED").count }.by(1)
    expect(response).to have_http_status(:ok)
    expect(json["status"]).to eq("COMPLETE")
    expect(json["steps"].map { |s| s["status"] }).to all(eq("CERTIFIED"))

    assembly.reload
    expect(assembly.current_status).to eq("CERTIFIED")
  end
end
