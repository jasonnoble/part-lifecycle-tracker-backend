require "rails_helper"

# Integration-level BOM explosion: drive the real demand path end-to-end through
# POST /customer-orders, then run the enqueued BomExplosionJob(s) and assert the
# explosion's persisted effects (reservation, supplier PO line, CO advancement).
#
# Complements spec/jobs/bom_explosion_job_spec.rb, which exercises the service
# logic directly. Here the line objects, enqueue, and dequeue all flow through
# the controller + ActiveJob, so this proves the wiring (controller enqueues one
# job per line; the job's #perform reconstitutes the line and applies the
# explosion) — not just the service in isolation.
#
# Real PostgreSQL, no mocking; the reservation invariants live in the DB. Tagged
# openapi: false so running the explosion (which mutates beyond the recorded POST
# 201 response) does not churn doc/openapi.yaml — the CO create example is pinned
# in spec/requests/customer_orders_spec.rb.
RSpec.describe "BOM explosion (integration)", type: :request, openapi: false do
  include ActiveJob::TestHelper

  # Reservation marker written by BomExplosionService for a given line — the same
  # anchor JAS-42's job spec asserts on.
  def reserve_log_for(line)
    StockAuditLog.where(part_definition: line.part_definition, reason: "CO line reserve #{line.id}")
  end

  def create_order(part_number:, quantity:, customer_name: "Powell Motors")
    post "/customer-orders", params: {
      customerName: customer_name,
      lines: [ { partNumber: part_number, quantity: quantity } ]
    }, as: :json
    expect(response).to have_http_status(:created)
    CustomerOrder.find(JSON.parse(response.body)["id"])
  end

  describe "in-stock line" do
    it "reserves the full quantity, advances the order, and raises no supplier PO" do
      part = create(:part_definition, part_number: "THE-HOMER-001", name: "The Homer")
      create(:stock, part_definition: part, quantity_on_hand: 10, quantity_reserved: 0)

      order = perform_enqueued_jobs { create_order(part_number: "THE-HOMER-001", quantity: 5) }
      line = order.customer_order_lines.sole

      expect(Stock.find_by(part_definition: part).quantity_reserved).to eq(5)
      expect(reserve_log_for(line).sum(:change_amount)).to eq(5)
      expect(SupplierPurchaseOrderLine.count).to eq(0)
      expect(order.reload.status).to eq("IN_FULFILLMENT")
    end
  end

  describe "out-of-stock line" do
    it "creates a NEEDS_ORDERING supplier PO line for the full quantity and reserves nothing" do
      part = create(:part_definition, part_number: "THE-HOMER-001", name: "The Homer")
      create(:stock, part_definition: part, quantity_on_hand: 0, quantity_reserved: 0)

      order = perform_enqueued_jobs { create_order(part_number: "THE-HOMER-001", quantity: 5) }

      expect(Stock.find_by(part_definition: part).quantity_reserved).to eq(0)
      expect(StockAuditLog.where(part_definition: part).count).to eq(0)

      po_line = SupplierPurchaseOrderLine.sole
      expect(po_line.part_definition).to eq(part)
      expect(po_line.quantity).to eq(5)
      expect(po_line.status).to eq("NEEDS_ORDERING")
      expect(po_line.supplier_purchase_order.customer_order).to eq(order)
      expect(order.reload.status).to eq("IN_FULFILLMENT")
    end
  end

  describe "partial line (order 5, stock 3)" do
    it "reserves the 3 on hand and raises a PO line for the 2-unit shortfall only" do
      part = create(:part_definition, part_number: "THE-HOMER-001", name: "The Homer")
      create(:stock, part_definition: part, quantity_on_hand: 3, quantity_reserved: 0)

      order = perform_enqueued_jobs { create_order(part_number: "THE-HOMER-001", quantity: 5) }
      line = order.customer_order_lines.sole

      expect(Stock.find_by(part_definition: part).quantity_reserved).to eq(3)
      expect(reserve_log_for(line).sum(:change_amount)).to eq(3)

      po_line = SupplierPurchaseOrderLine.sole
      expect(po_line.quantity).to eq(2)
      expect(po_line.status).to eq("NEEDS_ORDERING")
      expect(order.reload.status).to eq("IN_FULFILLMENT")
    end
  end

  describe "a multi-line order" do
    it "explodes each line independently (one in stock, one short)" do
      homer = create(:part_definition, part_number: "THE-HOMER-001", name: "The Homer")
      horn = create(:part_definition, part_number: "HORN-LCC-001", name: "La Cucaracha Horn")
      create(:stock, part_definition: homer, quantity_on_hand: 10, quantity_reserved: 0)
      create(:stock, part_definition: horn, quantity_on_hand: 0, quantity_reserved: 0)

      order = perform_enqueued_jobs do
        post "/customer-orders", params: {
          customerName: "Powell Motors",
          lines: [
            { partNumber: "THE-HOMER-001", quantity: 4 },
            { partNumber: "HORN-LCC-001", quantity: 2 }
          ]
        }, as: :json
        expect(response).to have_http_status(:created)
        CustomerOrder.find(JSON.parse(response.body)["id"])
      end

      expect(Stock.find_by(part_definition: homer).quantity_reserved).to eq(4)
      expect(Stock.find_by(part_definition: horn).quantity_reserved).to eq(0)

      po_line = SupplierPurchaseOrderLine.sole
      expect(po_line.part_definition).to eq(horn)
      expect(po_line.quantity).to eq(2)
      expect(po_line.status).to eq("NEEDS_ORDERING")
      expect(order.reload.status).to eq("IN_FULFILLMENT")
    end
  end

  describe "idempotency through the full path" do
    it "does not double-reserve or duplicate the PO line when the job runs twice" do
      part = create(:part_definition, part_number: "THE-HOMER-001", name: "The Homer")
      create(:stock, part_definition: part, quantity_on_hand: 3, quantity_reserved: 0)

      order = create_order(part_number: "THE-HOMER-001", quantity: 5)
      line = order.customer_order_lines.sole

      # Run the explosion for this line twice, simulating an at-least-once retry.
      BomExplosionJob.perform_now(line)
      BomExplosionJob.perform_now(line)

      expect(Stock.find_by(part_definition: part).quantity_reserved).to eq(3)
      expect(reserve_log_for(line).count).to eq(1)

      # Invariant: at most one open NEEDS_ORDERING line per customer_order + part.
      lines = SupplierPurchaseOrderLine
        .joins(:supplier_purchase_order)
        .where(part_definition: part, supplier_purchase_orders: { customer_order_id: order.id }, status: "NEEDS_ORDERING")
      expect(lines.count).to eq(1)
      expect(lines.sole.quantity).to eq(2)
      expect(SupplierPurchaseOrder.where(customer_order: order).count).to eq(1)
      expect(order.reload.status).to eq("IN_FULFILLMENT")
    end
  end
end
