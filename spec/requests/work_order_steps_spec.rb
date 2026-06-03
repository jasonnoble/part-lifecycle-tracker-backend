require "rails_helper"

RSpec.describe "Work Order step actions", type: :request do
  def json
    JSON.parse(response.body)
  end

  # Pinned literals (not FactoryBot sequences) so the generated OpenAPI example
  # is deterministic.
  let(:homer) { create(:part_definition, part_number: "THE-HOMER-001", name: "The Homer") }
  let(:muzzle) { create(:part_definition, part_number: "MUZZLE-001", name: "Muzzle") }
  let(:dome) { create(:part_definition, part_number: "DOME-TRANS-001", name: "Transparent Dome") }
  let(:horn) { create(:part_definition, part_number: "HORN-001", name: "Horn") }

  let!(:assembly_instance) { create(:part_instance, part_definition: homer, serial_number: "HMR-0047") }
  let(:work_order) { create(:work_order, part_definition: homer, part_instance: assembly_instance, status: "OPEN") }

  # BOM items on the homer.
  let!(:muzzle_bom) { create(:bom_item, parent: homer, child: muzzle, quantity: 1) }
  let!(:dome_bom) { create(:bom_item, parent: homer, child: dome, quantity: 1) }

  # The canonical rule: muzzle must be installed (and certified) before the dome.
  let!(:dependency) { create(:bom_item_dependency, prerequisite: muzzle_bom, dependent: dome_bom) }

  let(:muzzle_step) { create(:work_order_step, work_order: work_order, bom_item: muzzle_bom, status: "PENDING") }
  let(:dome_step) { create(:work_order_step, work_order: work_order, bom_item: dome_bom, status: "PENDING") }

  # The serialized component being installed into the assembly.
  let!(:component_instance) { create(:part_instance, part_definition: muzzle, serial_number: "MZL-0001") }

  # Personas: the actor is the authenticated user (JAS-79). Emails are pinned
  # (not faker) because they land in the captured OpenAPI examples and the doc
  # drift gate needs byte-identical regeneration; names never appear in these
  # responses, so the factory fakers them. Both installers — four-eyes is an
  # identity rule, so two installers still satisfy it.
  let(:installer) { create(:user, :installer, email: "jamie.torres@example.com") }
  let(:validator) { create(:user, :installer, email: "riley.park@example.com") }
  let(:qa) { create(:user, :qa_engineer, email: "dr.quinn@example.com") }

  describe "POST /work-orders/:id/steps/:step_id/install" do
    before { sign_in installer }

    it "installs a step with no prerequisites and appends an INSTALLED lifecycle event" do
      expect {
        post "/work-orders/#{work_order.id}/steps/#{muzzle_step.id}/install",
          params: { installedSerial: "MZL-0001" }, as: :json
      }.to change { component_instance.lifecycle_events.where(event_type: "INSTALLED").count }.by(1)

      expect(response).to have_http_status(:ok)
      step = json["steps"].find { |s| s["id"] == muzzle_step.id }
      expect(step["status"]).to eq("INSTALLED")
      expect(step["installedActor"]).to eq(installer.email)
      expect(step["installedPartInstanceId"]).to eq(component_instance.id)

      muzzle_step.reload
      expect(muzzle_step.installed_at).to be_present
      component_instance.reload
      expect(component_instance.current_status).to eq("INSTALLED")
      event = component_instance.lifecycle_events.where(event_type: "INSTALLED").last
      expect(event.actor).to eq(installer.email)
      expect(event.recorded_at).to be_present
    end

    it "returns 409 DEPENDENCY_NOT_MET naming the blocking part when a prerequisite is not certified" do
      muzzle_step # PENDING
      post "/work-orders/#{work_order.id}/steps/#{dome_step.id}/install",
        params: { installedSerial: "MZL-0001" }, as: :json

      expect(response).to have_http_status(:conflict)
      expect(json["code"]).to eq("DEPENDENCY_NOT_MET")
      expect(json["error"]).to include("MUZZLE-001")
      dome_step.reload
      expect(dome_step.status).to eq("PENDING")
    end

    it "allows the dependent step once the prerequisite step is certified (muzzle before dome)" do
      # Install -> validate -> certify the muzzle step, acting as each persona.
      post "/work-orders/#{work_order.id}/steps/#{muzzle_step.id}/install",
        params: { installedSerial: "MZL-0001" }, as: :json
      expect(response).to have_http_status(:ok)

      sign_in validator
      post "/work-orders/#{work_order.id}/steps/#{muzzle_step.id}/validate", as: :json
      expect(response).to have_http_status(:ok)

      sign_in qa
      post "/work-orders/#{work_order.id}/steps/#{muzzle_step.id}/certify", as: :json
      expect(response).to have_http_status(:ok)

      sign_in installer
      dome_component = create(:part_instance, part_definition: dome, serial_number: "DOME-0001")
      post "/work-orders/#{work_order.id}/steps/#{dome_step.id}/install",
        params: { installedSerial: "DOME-0001" }, as: :json

      expect(response).to have_http_status(:ok)
      step = json["steps"].find { |s| s["id"] == dome_step.id }
      expect(step["status"]).to eq("INSTALLED")
      expect(dome_component.reload.current_status).to eq("INSTALLED")
    end

    it "returns 409 INVALID_STEP_STATE when the step is not PENDING" do
      muzzle_step.update!(status: "INSTALLED", installed_actor: installer.email, installed_at: Time.current)
      post "/work-orders/#{work_order.id}/steps/#{muzzle_step.id}/install",
        params: { installedSerial: "MZL-0001" }, as: :json

      expect(response).to have_http_status(:conflict)
      expect(json["code"]).to eq("INVALID_STEP_STATE")
    end

    it "returns 422 when the installedSerial is unknown" do
      post "/work-orders/#{work_order.id}/steps/#{muzzle_step.id}/install",
        params: { installedSerial: "NO-SUCH-SN" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
    end

    it "returns 404 for an unknown work order" do
      post "/work-orders/#{SecureRandom.uuid}/steps/#{muzzle_step.id}/install",
        params: { installedSerial: "MZL-0001" }, as: :json
      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end

    it "returns 404 for an unknown step" do
      post "/work-orders/#{work_order.id}/steps/#{SecureRandom.uuid}/install",
        params: { installedSerial: "MZL-0001" }, as: :json
      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end

    it "returns 403 FORBIDDEN when the authenticated user is not an installer" do
      sign_in qa

      post "/work-orders/#{work_order.id}/steps/#{muzzle_step.id}/install",
        params: { installedSerial: "MZL-0001" }, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("FORBIDDEN")
      expect(muzzle_step.reload.status).to eq("PENDING")
    end
  end

  describe "POST /work-orders/:id/steps/:step_id/validate" do
    before do
      muzzle_step.update!(status: "INSTALLED", installed_actor: installer.email, installed_at: Time.current,
        installed_part_instance: component_instance)
      sign_in validator
    end

    it "validates the step by a different actor" do
      post "/work-orders/#{work_order.id}/steps/#{muzzle_step.id}/validate", as: :json

      expect(response).to have_http_status(:ok)
      step = json["steps"].find { |s| s["id"] == muzzle_step.id }
      expect(step["status"]).to eq("VALIDATED")
      expect(step["validatedActor"]).to eq(validator.email)
      expect(muzzle_step.reload.validated_at).to be_present
    end

    it "returns 409 SAME_ACTOR when the validator is the installer (4-eyes)" do
      sign_in installer

      post "/work-orders/#{work_order.id}/steps/#{muzzle_step.id}/validate", as: :json

      expect(response).to have_http_status(:conflict)
      expect(json["code"]).to eq("SAME_ACTOR")
      expect(muzzle_step.reload.status).to eq("INSTALLED")
    end

    it "returns 403 FORBIDDEN when the authenticated user is not an installer" do
      sign_in qa

      post "/work-orders/#{work_order.id}/steps/#{muzzle_step.id}/validate", as: :json

      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("FORBIDDEN")
      expect(muzzle_step.reload.status).to eq("INSTALLED")
    end

    it "returns 409 INVALID_STEP_STATE when the step is not INSTALLED" do
      muzzle_step.update!(status: "PENDING", installed_actor: nil, installed_at: nil, installed_part_instance: nil)
      post "/work-orders/#{work_order.id}/steps/#{muzzle_step.id}/validate", as: :json

      expect(response).to have_http_status(:conflict)
      expect(json["code"]).to eq("INVALID_STEP_STATE")
    end
  end

  describe "POST /work-orders/:id/steps/:step_id/certify" do
    before do
      muzzle_step.update!(status: "VALIDATED", installed_actor: installer.email, installed_at: Time.current,
        validated_actor: validator.email, validated_at: Time.current, installed_part_instance: component_instance)
      sign_in qa
    end

    it "certifies the step when the authenticated user has the qa_engineer role" do
      post "/work-orders/#{work_order.id}/steps/#{muzzle_step.id}/certify", as: :json

      expect(response).to have_http_status(:ok)
      step = json["steps"].find { |s| s["id"] == muzzle_step.id }
      expect(step["status"]).to eq("CERTIFIED")
      expect(step["certifiedActor"]).to eq(qa.email)
      expect(muzzle_step.reload.certified_at).to be_present
    end

    it "returns 403 FORBIDDEN when the authenticated user's role is not qa_engineer" do
      sign_in validator

      post "/work-orders/#{work_order.id}/steps/#{muzzle_step.id}/certify", as: :json

      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("FORBIDDEN")
      expect(muzzle_step.reload.status).to eq("VALIDATED")
    end

    it "returns 409 INVALID_STEP_STATE when the step is not VALIDATED" do
      muzzle_step.update!(status: "INSTALLED", validated_actor: nil, validated_at: nil)
      post "/work-orders/#{work_order.id}/steps/#{muzzle_step.id}/certify", as: :json

      expect(response).to have_http_status(:conflict)
      expect(json["code"]).to eq("INVALID_STEP_STATE")
    end
  end
end
