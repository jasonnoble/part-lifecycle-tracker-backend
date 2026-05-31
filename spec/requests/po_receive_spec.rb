require "rails_helper"

RSpec.describe "Supplier PO receive", type: :request do
  def json
    JSON.parse(response.body)
  end

  let(:horn) { create(:part_definition, part_number: "HORN-LCC-001", name: "La Cucaracha Horn") }
  let(:dome) { create(:part_definition, part_number: "DOME-XPT-001", name: "Transparent Dome") }
  let(:po) { create(:supplier_purchase_order, status: "OPEN") }
  let!(:horn_line) do
    create(:supplier_purchase_order_line, supplier_purchase_order: po, part_definition: horn, quantity: 2, status: "ORDERED")
  end

  describe "POST /supplier-purchase-orders/:id/receive" do
    it "receives all lines fully: creates instances, RECEIVED events, increments stock, writes audit log, status RECEIVED" do
      expect {
        post "/supplier-purchase-orders/#{po.id}/receive", params: {
          lines: [ { lineId: horn_line.id, quantity: 2, serials: %w[HMR-0001 HMR-0002] } ]
        }, as: :json
      }.to change(PartInstance, :count).by(2)
        .and change(LifecycleEvent, :count).by(2)
        .and change(StockAuditLog, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("RECEIVED")
      expect(json["lines"].first["status"]).to eq("RECEIVED")
      expect(json["lines"].first["quantityReceived"]).to eq(2)

      instances = PartInstance.where(serial_number: %w[HMR-0001 HMR-0002])
      expect(instances.count).to eq(2)
      instances.each do |inst|
        expect(inst.current_status).to eq("RECEIVED")
        expect(inst.part_definition_id).to eq(horn.id)
        event = inst.lifecycle_events.first
        expect(event.event_type).to eq("RECEIVED")
        expect(event.actor).to eq("system/receive")
        expect(event.recorded_at).to be_present
      end

      expect(Stock.find_by(part_definition: horn).quantity_on_hand).to eq(2)
      log = StockAuditLog.find_by(part_definition: horn)
      expect(log.change_amount).to eq(2)
      expect(log.reason).to include(po.id)
    end

    it "increments existing stock rather than resetting it" do
      create(:stock, part_definition: horn, quantity_on_hand: 5)

      post "/supplier-purchase-orders/#{po.id}/receive", params: {
        lines: [ { lineId: horn_line.id, quantity: 2, serials: %w[HMR-0001 HMR-0002] } ]
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(Stock.find_by(part_definition: horn).quantity_on_hand).to eq(7)
    end

    it "receives a partial quantity: PO and line are PARTIALLY_RECEIVED" do
      post "/supplier-purchase-orders/#{po.id}/receive", params: {
        lines: [ { lineId: horn_line.id, quantity: 1, serials: %w[HMR-0001] } ]
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("PARTIALLY_RECEIVED")
      expect(json["lines"].first["status"]).to eq("PARTIALLY_RECEIVED")
      expect(json["lines"].first["quantityReceived"]).to eq(1)
      expect(Stock.find_by(part_definition: horn).quantity_on_hand).to eq(1)
    end

    it "marks PO PARTIALLY_RECEIVED when one of several lines is unreceived" do
      dome_line = create(:supplier_purchase_order_line, supplier_purchase_order: po, part_definition: dome, quantity: 1, status: "ORDERED")

      post "/supplier-purchase-orders/#{po.id}/receive", params: {
        lines: [ { lineId: horn_line.id, quantity: 2, serials: %w[HMR-0001 HMR-0002] } ]
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("PARTIALLY_RECEIVED")
      lines = json["lines"].index_by { |l| l["id"] }
      expect(lines[horn_line.id]["status"]).to eq("RECEIVED")
      expect(lines[dome_line.id]["status"]).to eq("ORDERED")
    end

    it "returns 422 and creates nothing when a serial is duplicated within the request" do
      expect {
        post "/supplier-purchase-orders/#{po.id}/receive", params: {
          lines: [ { lineId: horn_line.id, quantity: 2, serials: %w[HMR-0001 HMR-0001] } ]
        }, as: :json
      }.to change(PartInstance, :count).by(0)
        .and change(StockAuditLog, :count).by(0)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
    end

    it "returns 422 and rolls back when a serial is already in use" do
      create(:part_instance, serial_number: "HMR-0001")
      create(:stock, part_definition: horn, quantity_on_hand: 3)

      expect {
        post "/supplier-purchase-orders/#{po.id}/receive", params: {
          lines: [ { lineId: horn_line.id, quantity: 2, serials: %w[HMR-0001 HMR-0002] } ]
        }, as: :json
      }.to change(PartInstance, :count).by(0)
        .and change(StockAuditLog, :count).by(0)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
      expect(Stock.find_by(part_definition: horn).quantity_on_hand).to eq(3)
      expect(po.reload.status).to eq("OPEN")
    end

    it "returns 422 when a serial is blank" do
      post "/supplier-purchase-orders/#{po.id}/receive", params: {
        lines: [ { lineId: horn_line.id, quantity: 2, serials: [ "HMR-0001", "" ] } ]
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
      expect(PartInstance.count).to eq(0)
    end

    it "returns 422 when serials count does not match quantity" do
      post "/supplier-purchase-orders/#{po.id}/receive", params: {
        lines: [ { lineId: horn_line.id, quantity: 2, serials: %w[HMR-0001] } ]
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
    end

    it "returns 422 when a lineId does not belong to this PO" do
      other_line = create(:supplier_purchase_order_line, part_definition: horn, quantity: 1)

      post "/supplier-purchase-orders/#{po.id}/receive", params: {
        lines: [ { lineId: other_line.id, quantity: 1, serials: %w[HMR-0001] } ]
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("VALIDATION_FAILED")
      expect(PartInstance.count).to eq(0)
    end

    it "rolls back instances and stock when a write fails mid-transaction" do
      create(:stock, part_definition: horn, quantity_on_hand: 4)
      allow(StockAuditLog).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "boom")

      expect {
        post "/supplier-purchase-orders/#{po.id}/receive", params: {
          lines: [ { lineId: horn_line.id, quantity: 2, serials: %w[HMR-0001 HMR-0002] } ]
        }, as: :json
      }.to raise_error(ActiveRecord::StatementInvalid)

      expect(PartInstance.where(serial_number: %w[HMR-0001 HMR-0002]).count).to eq(0)
      expect(Stock.find_by(part_definition: horn).quantity_on_hand).to eq(4)
      expect(po.reload.status).to eq("OPEN")
    end

    it "returns 404 when the PO does not exist" do
      post "/supplier-purchase-orders/00000000-0000-0000-0000-000000000000/receive", params: {
        lines: [ { lineId: horn_line.id, quantity: 1, serials: %w[HMR-0001] } ]
      }, as: :json

      expect(response).to have_http_status(:not_found)
      expect(json["code"]).to eq("NOT_FOUND")
    end
  end
end
