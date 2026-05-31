require "rails_helper"

# Real PostgreSQL, no mocking — the reservation invariants live in the DB.
# Each example drives the job's #perform synchronously (the :test queue adapter
# does not run enqueued jobs) and asserts the resulting persisted state.
RSpec.describe BomExplosionJob, type: :job do
  let(:part) { create(:part_definition) }
  let(:customer_order) { create(:customer_order, status: "OPEN") }

  def line(quantity:)
    create(:customer_order_line, customer_order: customer_order, part_definition: part, quantity: quantity)
  end

  def perform(line)
    described_class.new.perform(line)
  end

  describe "in-stock path (available >= quantity)" do
    before { create(:stock, part_definition: part, quantity_on_hand: 10, quantity_reserved: 0) }

    it "reserves the full ordered quantity, advances the order, and raises no PO line" do
      col = line(quantity: 5)

      perform(col)

      expect(Stock.find_by(part_definition: part).quantity_reserved).to eq(5)
      expect(customer_order.reload.status).to eq("IN_FULFILLMENT")
      expect(SupplierPurchaseOrderLine.count).to eq(0)
      expect(
        StockAuditLog.where(part_definition: part, reason: "CO line reserve #{col.id}").sum(:change_amount)
      ).to eq(5)
    end
  end

  describe "out-of-stock path (available == 0)" do
    before { create(:stock, part_definition: part, quantity_on_hand: 0, quantity_reserved: 0) }

    it "creates a NEEDS_ORDERING supplier PO line for the full quantity and reserves nothing" do
      col = line(quantity: 5)

      perform(col)

      expect(Stock.find_by(part_definition: part).quantity_reserved).to eq(0)
      expect(StockAuditLog.count).to eq(0)

      po_line = SupplierPurchaseOrderLine.sole
      expect(po_line.part_definition).to eq(part)
      expect(po_line.quantity).to eq(5)
      expect(po_line.status).to eq("NEEDS_ORDERING")
      expect(po_line.supplier_purchase_order.customer_order).to eq(customer_order)
      expect(customer_order.reload.status).to eq("IN_FULFILLMENT")
    end

    it "works when no stock row exists yet (creates one at zero)" do
      Stock.where(part_definition: part).delete_all
      col = line(quantity: 3)

      perform(col)

      expect(Stock.find_by(part_definition: part).quantity_reserved).to eq(0)
      expect(SupplierPurchaseOrderLine.sole.quantity).to eq(3)
    end
  end

  describe "partial path (order 5, stock 3)" do
    before { create(:stock, part_definition: part, quantity_on_hand: 3, quantity_reserved: 0) }

    it "reserves 3 and raises a PO line for the 2-unit shortfall" do
      col = line(quantity: 5)

      perform(col)

      expect(Stock.find_by(part_definition: part).quantity_reserved).to eq(3)

      po_line = SupplierPurchaseOrderLine.sole
      expect(po_line.quantity).to eq(2)
      expect(po_line.status).to eq("NEEDS_ORDERING")
      expect(customer_order.reload.status).to eq("IN_FULFILLMENT")
    end

    it "accounts for stock already reserved by another order" do
      Stock.find_by(part_definition: part).update!(quantity_reserved: 1)
      col = line(quantity: 5)

      perform(col)

      # available was 3 - 1 = 2, so reserve 2 more (total 3), shortfall 3.
      expect(Stock.find_by(part_definition: part).quantity_reserved).to eq(3)
      expect(SupplierPurchaseOrderLine.sole.quantity).to eq(3)
    end
  end

  describe "idempotency" do
    it "does not double-reserve on a second run (in-stock)" do
      create(:stock, part_definition: part, quantity_on_hand: 10, quantity_reserved: 0)
      col = line(quantity: 5)

      perform(col)
      perform(col)

      expect(Stock.find_by(part_definition: part).quantity_reserved).to eq(5)
      expect(StockAuditLog.where(part_definition: part).count).to eq(1)
      expect(customer_order.reload.status).to eq("IN_FULFILLMENT")
    end

    it "does not duplicate the PO line or double-reserve on a second run (partial)" do
      create(:stock, part_definition: part, quantity_on_hand: 3, quantity_reserved: 0)
      col = line(quantity: 5)

      perform(col)
      perform(col)

      expect(Stock.find_by(part_definition: part).quantity_reserved).to eq(3)
      expect(StockAuditLog.where(part_definition: part).count).to eq(1)

      lines = SupplierPurchaseOrderLine.where(part_definition: part)
      expect(lines.count).to eq(1)
      expect(lines.sole.quantity).to eq(2)
      expect(SupplierPurchaseOrder.count).to eq(1)
    end

    it "does not duplicate the PO line on a second run (out-of-stock)" do
      create(:stock, part_definition: part, quantity_on_hand: 0, quantity_reserved: 0)
      col = line(quantity: 5)

      perform(col)
      perform(col)

      expect(SupplierPurchaseOrderLine.where(part_definition: part).count).to eq(1)
      expect(SupplierPurchaseOrder.count).to eq(1)
    end
  end
end
