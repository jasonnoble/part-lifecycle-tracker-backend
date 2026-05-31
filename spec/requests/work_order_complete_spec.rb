require "rails_helper"

RSpec.describe "Work Order completion", type: :request do
  def json
    JSON.parse(response.body)
  end

  # Pinned literals (not FactoryBot sequences) so the generated OpenAPI example
  # is deterministic.
  let(:homer) { create(:part_definition, part_number: "THE-HOMER-001", name: "The Homer") }
  let(:muzzle) { create(:part_definition, part_number: "MUZZLE-001", name: "Muzzle") }
  let(:dome) { create(:part_definition, part_number: "DOME-TRANS-001", name: "Transparent Dome") }

  let!(:assembly_instance) { create(:part_instance, part_definition: homer, serial_number: "HMR-0047", current_status: "IN_ASSEMBLY") }
  let(:work_order) { create(:work_order, part_definition: homer, part_instance: assembly_instance, status: "OPEN") }

  let!(:muzzle_bom) { create(:bom_item, parent: homer, child: muzzle, quantity: 1) }
  let!(:dome_bom) { create(:bom_item, parent: homer, child: dome, quantity: 1) }

  let!(:muzzle_step) { create(:work_order_step, work_order: work_order, bom_item: muzzle_bom, status: "CERTIFIED") }
  let!(:dome_step) { create(:work_order_step, work_order: work_order, bom_item: dome_bom, status: "CERTIFIED") }

  describe "POST /work-orders/:id/complete" do
    it "completes the work order and appends a CERTIFIED lifecycle event to the part instance" do
      expect {
        post "/work-orders/#{work_order.id}/complete", as: :json
      }.to change { assembly_instance.lifecycle_events.where(event_type: "CERTIFIED").count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("COMPLETE")
      expect(json["steps"].map { |s| s["status"] }).to all(eq("CERTIFIED"))

      expect(work_order.reload.status).to eq("COMPLETE")

      assembly_instance.reload
      expect(assembly_instance.current_status).to eq("CERTIFIED")
      event = assembly_instance.lifecycle_events.where(event_type: "CERTIFIED").last
      expect(event.recorded_at).to be_present
      expect(event.actor).to be_present
    end

    it "returns 422 STEPS_NOT_CERTIFIED and leaves status unchanged when a step is not CERTIFIED" do
      dome_step.update!(status: "INSTALLED")

      expect {
        post "/work-orders/#{work_order.id}/complete", as: :json
      }.not_to change { assembly_instance.lifecycle_events.count }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("STEPS_NOT_CERTIFIED")
      expect(work_order.reload.status).to eq("OPEN")
    end

    it "returns 404 for an unknown work order" do
      post "/work-orders/#{SecureRandom.uuid}/complete", as: :json
      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end

    it "returns 422 INVALID_STATE when the work order is already COMPLETE", openapi: false do
      work_order.update!(status: "COMPLETE")

      post "/work-orders/#{work_order.id}/complete", as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("INVALID_STATE")
    end
  end
end
