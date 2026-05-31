require "rails_helper"

RSpec.describe "Supplier purchase orders", type: :request do
  def json
    JSON.parse(response.body)
  end

  describe "POST /supplier-purchase-orders" do
    it "creates a PO with lines (201, OPEN, lines NEEDS_ORDERING)" do
      create(:part_definition, part_number: "HORN-LCC-001", name: "La Cucaracha Horn")

      post "/supplier-purchase-orders", params: {
        supplierId: "VENDOR-ACME-001",
        lines: [ { partNumber: "HORN-LCC-001", quantity: 50 } ]
      }, as: :json

      expect(response).to have_http_status(:created)
      expect(json["supplierId"]).to eq("VENDOR-ACME-001")
      expect(json["status"]).to eq("OPEN")
      expect(json["lines"].size).to eq(1)

      line = json["lines"].first
      expect(line["partNumber"]).to eq("HORN-LCC-001")
      expect(line["partName"]).to eq("La Cucaracha Horn")
      expect(line["quantity"]).to eq(50)
      expect(line["quantityReceived"]).to eq(0)
      expect(line["status"]).to eq("NEEDS_ORDERING")
    end

    it "persists the PO and its lines" do
      create(:part_definition, part_number: "HORN-LCC-001")

      expect {
        post "/supplier-purchase-orders", params: {
          supplierId: "VENDOR-ACME-001",
          lines: [ { partNumber: "HORN-LCC-001", quantity: 50 } ]
        }, as: :json
      }.to change(SupplierPurchaseOrder, :count).by(1)
        .and change(SupplierPurchaseOrderLine, :count).by(1)
    end

    it "returns 422 when there are no lines" do
      post "/supplier-purchase-orders", params: {
        supplierId: "VENDOR-ACME-001",
        lines: []
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
    end

    it "returns 422 when supplierId is blank" do
      create(:part_definition, part_number: "HORN-LCC-001")

      post "/supplier-purchase-orders", params: {
        supplierId: "",
        lines: [ { partNumber: "HORN-LCC-001", quantity: 50 } ]
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
    end

    it "returns 422 when a partNumber is unknown" do
      post "/supplier-purchase-orders", params: {
        supplierId: "VENDOR-ACME-001",
        lines: [ { partNumber: "NOPE-999", quantity: 50 } ]
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
      expect(SupplierPurchaseOrder.count).to eq(0)
    end
  end

  describe "GET /supplier-purchase-orders" do
    it "returns a paginated list" do
      create_list(:supplier_purchase_order, 2)

      get "/supplier-purchase-orders"

      expect(response).to have_http_status(:ok)
      expect(json["data"].size).to eq(2)
      expect(json["meta"]).to include("currentPage", "totalPages", "totalCount" => 2)
    end
  end

  describe "GET /supplier-purchase-orders/:id" do
    it "returns the PO with its lines including part details" do
      part = create(:part_definition, part_number: "HORN-LCC-001", name: "La Cucaracha Horn")
      po = create(:supplier_purchase_order, supplier_id: "VENDOR-ACME-001")
      create(:supplier_purchase_order_line, supplier_purchase_order: po, part_definition: part, quantity: 50)

      get "/supplier-purchase-orders/#{po.id}"

      expect(response).to have_http_status(:ok)
      expect(json["id"]).to eq(po.id)
      expect(json["supplierId"]).to eq("VENDOR-ACME-001")
      expect(json["lines"].size).to eq(1)

      line = json["lines"].first
      expect(line["partNumber"]).to eq("HORN-LCC-001")
      expect(line["partName"]).to eq("La Cucaracha Horn")
      expect(line["quantity"]).to eq(50)
      expect(line["quantityReceived"]).to eq(0)
      expect(line["status"]).to eq("NEEDS_ORDERING")
    end

    it "returns 404 for an unknown id" do
      get "/supplier-purchase-orders/00000000-0000-0000-0000-000000000000"

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end
end
