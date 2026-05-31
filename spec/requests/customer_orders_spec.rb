require "rails_helper"

RSpec.describe "Customer orders", type: :request do
  include ActiveJob::TestHelper

  def json
    JSON.parse(response.body)
  end

  describe "POST /customer-orders" do
    it "creates a CO with lines (201, OPEN) and enqueues a BomExplosionJob per line" do
      create(:part_definition, part_number: "THE-HOMER-001", name: "The Homer")
      create(:part_definition, part_number: "HORN-LCC-001", name: "La Cucaracha Horn")

      expect {
        post "/customer-orders", params: {
          customerName: "Powell Motors",
          lines: [
            { partNumber: "THE-HOMER-001", quantity: 5 },
            { partNumber: "HORN-LCC-001", quantity: 2 }
          ]
        }, as: :json
      }.to have_enqueued_job(BomExplosionJob).exactly(2).times

      expect(response).to have_http_status(:created)
      expect(json["customerName"]).to eq("Powell Motors")
      expect(json["status"]).to eq("OPEN")
      expect(json["lines"].size).to eq(2)

      line = json["lines"].first
      expect(line["partNumber"]).to eq("THE-HOMER-001")
      expect(line["partName"]).to eq("The Homer")
      expect(line["quantity"]).to eq(5)
    end

    it "persists the CO and its lines" do
      create(:part_definition, part_number: "THE-HOMER-001")

      expect {
        post "/customer-orders", params: {
          customerName: "Powell Motors",
          lines: [ { partNumber: "THE-HOMER-001", quantity: 5 } ]
        }, as: :json
      }.to change(CustomerOrder, :count).by(1)
        .and change(CustomerOrderLine, :count).by(1)
    end

    it "returns 422 when there are no lines" do
      post "/customer-orders", params: {
        customerName: "Powell Motors",
        lines: []
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
      expect(CustomerOrder.count).to eq(0)
    end

    it "returns 422 when customerName is blank" do
      create(:part_definition, part_number: "THE-HOMER-001")

      post "/customer-orders", params: {
        customerName: "",
        lines: [ { partNumber: "THE-HOMER-001", quantity: 5 } ]
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
      expect(CustomerOrder.count).to eq(0)
    end

    it "returns 422 when a partNumber is unknown" do
      post "/customer-orders", params: {
        customerName: "Powell Motors",
        lines: [ { partNumber: "NOPE-999", quantity: 5 } ]
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
      expect(CustomerOrder.count).to eq(0)
    end

    it "does not enqueue any job when validation fails" do
      expect {
        post "/customer-orders", params: {
          customerName: "Powell Motors",
          lines: []
        }, as: :json
      }.not_to have_enqueued_job(BomExplosionJob)
    end
  end

  describe "GET /customer-orders" do
    it "returns a paginated list" do
      # Pin customer_names so the captured doc/openapi.yaml example is deterministic
      # (the factory's customer_name is a global FactoryBot sequence).
      create(:customer_order, customer_name: "Powell Motors")
      create(:customer_order, customer_name: "Springfield Taxi Co")

      get "/customer-orders"

      expect(response).to have_http_status(:ok)
      expect(json["data"].size).to eq(2)
      expect(json["meta"]).to include("currentPage", "totalPages", "totalCount" => 2)
    end
  end

  describe "GET /customer-orders/:id" do
    it "returns the CO with its lines including part details" do
      part = create(:part_definition, part_number: "THE-HOMER-001", name: "The Homer")
      co = create(:customer_order, customer_name: "Powell Motors")
      create(:customer_order_line, customer_order: co, part_definition: part, quantity: 5)

      get "/customer-orders/#{co.id}"

      expect(response).to have_http_status(:ok)
      expect(json["id"]).to eq(co.id)
      expect(json["customerName"]).to eq("Powell Motors")
      expect(json["status"]).to eq("OPEN")
      expect(json["lines"].size).to eq(1)

      line = json["lines"].first
      expect(line["partNumber"]).to eq("THE-HOMER-001")
      expect(line["partName"]).to eq("The Homer")
      expect(line["quantity"]).to eq(5)
    end

    it "returns 404 for an unknown id" do
      get "/customer-orders/00000000-0000-0000-0000-000000000000"

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end
end
