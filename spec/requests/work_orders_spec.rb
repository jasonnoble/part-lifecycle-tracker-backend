require "rails_helper"

RSpec.describe "Work Orders", type: :request do
  include ActiveJob::TestHelper

  def json
    JSON.parse(response.body)
  end

  # Pinned literals (not FactoryBot sequences) so the generated OpenAPI example
  # is deterministic.
  let(:homer) { create(:part_definition, part_number: "THE-HOMER-001", name: "The Homer") }
  let(:muzzle) { create(:part_definition, part_number: "MUZZLE-001", name: "Muzzle") }
  let(:dome) { create(:part_definition, part_number: "DOME-TRANS-001", name: "Transparent Dome") }
  let!(:instance) { create(:part_instance, part_definition: homer, serial_number: "HMR-0047") }

  let!(:muzzle_bom) { create(:bom_item, parent: homer, child: muzzle, quantity: 1) }
  let!(:dome_bom) { create(:bom_item, parent: homer, child: dome, quantity: 1) }

  describe "POST /work-orders" do
    it "creates an OPEN work order with one PENDING step per active BOM item and enqueues StockReservationJob" do
      expect {
        post "/work-orders", params: {
          partNumber: "THE-HOMER-001",
          serialNumber: "HMR-0047"
        }, as: :json
      }.to change(WorkOrder, :count).by(1)
        .and change(WorkOrderStep, :count).by(2)
        .and have_enqueued_job(StockReservationJob)

      expect(response).to have_http_status(:created)
      expect(json["status"]).to eq("OPEN")
      expect(json["partNumber"]).to eq("THE-HOMER-001")
      expect(json["serialNumber"]).to eq("HMR-0047")
      expect(json["steps"].length).to eq(2)
      expect(json["steps"].map { |s| s["status"] }).to all(eq("PENDING"))
      expect(json["steps"].map { |s| s["childPartNumber"] }).to match_array(%w[MUZZLE-001 DOME-TRANS-001])
      expect(json["steps"].first).to include("bomItemId", "childPartName", "installedActor", "validatedActor", "certifiedActor")
    end

    it "stores customerOrderLineId when provided" do
      # No CustomerOrderLine model yet (Track 4 demand side), but work_orders has a
      # real FK to customer_order_lines, so seed a row directly to satisfy it.
      customer_order = CustomerOrder.create!(customer_name: "Mr. Burns", status: "OPEN")
      col_id = SecureRandom.uuid
      ActiveRecord::Base.connection.exec_insert(
        "INSERT INTO customer_order_lines (id, customer_order_id, part_definition_id, quantity, created_at, updated_at) " \
        "VALUES ($1, $2, $3, 1, now(), now())",
        "seed_col",
        [
          ActiveRecord::Relation::QueryAttribute.new("id", col_id, ActiveRecord::Type::String.new),
          ActiveRecord::Relation::QueryAttribute.new("customer_order_id", customer_order.id, ActiveRecord::Type::String.new),
          ActiveRecord::Relation::QueryAttribute.new("part_definition_id", homer.id, ActiveRecord::Type::String.new)
        ]
      )

      post "/work-orders", params: {
        partNumber: "THE-HOMER-001",
        serialNumber: "HMR-0047",
        customerOrderLineId: col_id
      }, as: :json

      expect(response).to have_http_status(:created)
      expect(json["customerOrderLineId"]).to eq(col_id)
    end

    it "excludes soft-deleted BOM items from the steps" do
      dome_bom.update!(deleted_at: Time.current)

      post "/work-orders", params: {
        partNumber: "THE-HOMER-001",
        serialNumber: "HMR-0047"
      }, as: :json

      expect(response).to have_http_status(:created)
      expect(json["steps"].length).to eq(1)
      expect(json["steps"].first["childPartNumber"]).to eq("MUZZLE-001")
    end

    it "returns 404 for an unknown partNumber" do
      post "/work-orders", params: {
        partNumber: "NOPE-999",
        serialNumber: "HMR-0047"
      }, as: :json

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end

    it "returns 404 for an unknown serialNumber" do
      homer

      post "/work-orders", params: {
        partNumber: "THE-HOMER-001",
        serialNumber: "MISSING-SN"
      }, as: :json

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end

    it "returns 422 OPEN_WORK_ORDER_EXISTS when the serial already has a non-COMPLETE work order" do
      create(:work_order, part_definition: homer, part_instance: instance, status: "OPEN")

      post "/work-orders", params: {
        partNumber: "THE-HOMER-001",
        serialNumber: "HMR-0047"
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("OPEN_WORK_ORDER_EXISTS")
    end

    it "allows a new work order when the existing one is COMPLETE" do
      create(:work_order, part_definition: homer, part_instance: instance, status: "COMPLETE")

      post "/work-orders", params: {
        partNumber: "THE-HOMER-001",
        serialNumber: "HMR-0047"
      }, as: :json

      expect(response).to have_http_status(:created)
    end
  end

  describe "GET /work-orders" do
    it "lists work orders and filters by status" do
      open_wo = create(:work_order, part_definition: homer, part_instance: instance, status: "OPEN")
      other_instance = create(:part_instance, part_definition: homer, serial_number: "HMR-9999")
      create(:work_order, part_definition: homer, part_instance: other_instance, status: "COMPLETE")

      get "/work-orders", params: { status: "OPEN" }

      expect(response).to have_http_status(:ok)
      expect(json["data"].length).to eq(1)
      expect(json["data"].first["id"]).to eq(open_wo.id)
      expect(json["data"].first["status"]).to eq("OPEN")
      expect(json["meta"]).to include("currentPage", "totalPages", "totalCount")
    end
  end

  describe "GET /work-orders/:id" do
    it "returns the work order with its steps" do
      wo = create(:work_order, part_definition: homer, part_instance: instance, status: "OPEN")
      create(:work_order_step, work_order: wo, bom_item: muzzle_bom, status: "PENDING")

      get "/work-orders/#{wo.id}"

      expect(response).to have_http_status(:ok)
      expect(json["id"]).to eq(wo.id)
      expect(json["serialNumber"]).to eq("HMR-0047")
      expect(json["steps"].length).to eq(1)
      expect(json["steps"].first["childPartNumber"]).to eq("MUZZLE-001")
    end

    it "returns 404 for an unknown id" do
      get "/work-orders/#{SecureRandom.uuid}"

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end
end
