SeedHelper.track("Track 5 — Supplier POs + received instances (JAS-34)")

# Track 5 seeds the supply side of the demand-to-fulfillment chain:
#
#   1. ONE OPEN supplier PO for MARGE-FAM-001 — its line is still NEEDS_ORDERING
#      (awaiting receipt). Demonstrates the "not yet received" state.
#   2. ONE RECEIVED supplier PO for La Cucaracha Horns (HORN-LCC-001) — 50 part
#      instances HORN-LCC-0001..HORN-LCC-0050, each with a RECEIVED lifecycle
#      event, the PO + its line marked RECEIVED (quantity 50, quantity_received
#      50), and stocks.quantity_on_hand = 50 for HORN-LCC-001.
#
# Everything is idempotent: re-running must not duplicate POs, lines, the 50
# instances, their events, or the stock audit row.
#
# Cross-seed gotcha: Track 2 resets every stock row's quantity_on_hand to 0 on a
# full reseed. Track 5 runs AFTER Track 2, so it sets the HORN-LCC-001 stock
# level here and guards the stock_audit_logs insert on its `reason` so the audit
# entry is written at most once. There is no StockAuditLog model on this branch,
# so the audit row is inserted via sanitized SQL.

OPEN_PO_SUPPLIER_ID     = "VENDOR-ACME-001".freeze
OPEN_PO_PART_NUMBER     = "MARGE-FAM-001".freeze
OPEN_PO_QUANTITY        = 10

RECEIVED_PO_SUPPLIER_ID = "VENDOR-SPRINGFIELD-HORNS-001".freeze
RECEIVED_PO_PART_NUMBER = "HORN-LCC-001".freeze
RECEIVED_PO_QUANTITY    = 50
HORN_SERIAL_PREFIX      = "HORN-LCC-".freeze
HORN_STOCK_AUDIT_REASON = "Track 5 seed: received supplier PO for #{RECEIVED_PO_PART_NUMBER}".freeze

definitions = PartDefinition.where(part_number: [ OPEN_PO_PART_NUMBER, RECEIVED_PO_PART_NUMBER ]).index_by(&:part_number)

# --- 1. Open supplier PO (line still NEEDS_ORDERING) ------------------------

SeedHelper.step("seed OPEN supplier PO for #{OPEN_PO_PART_NUMBER} (#{OPEN_PO_SUPPLIER_ID})") do
  part = definitions.fetch(OPEN_PO_PART_NUMBER)
  po = SupplierPurchaseOrder.find_or_create_by!(supplier_id: OPEN_PO_SUPPLIER_ID, customer_order_id: nil) do |o|
    o.status = "OPEN"
  end

  SupplierPurchaseOrderLine.find_or_create_by!(
    supplier_purchase_order_id: po.id,
    part_definition_id: part.id
  ) do |line|
    line.quantity = OPEN_PO_QUANTITY
    line.quantity_received = 0
    line.status = "NEEDS_ORDERING"
  end
end

# --- 2. Received supplier PO + 50 instances + events + stock + audit --------

SeedHelper.step("seed RECEIVED supplier PO for #{RECEIVED_PO_PART_NUMBER} (#{RECEIVED_PO_SUPPLIER_ID})") do
  part = definitions.fetch(RECEIVED_PO_PART_NUMBER)

  po = SupplierPurchaseOrder.find_or_create_by!(supplier_id: RECEIVED_PO_SUPPLIER_ID, customer_order_id: nil) do |o|
    o.status = "RECEIVED"
  end
  po.update!(status: "RECEIVED") unless po.status == "RECEIVED"

  line = SupplierPurchaseOrderLine.find_or_create_by!(
    supplier_purchase_order_id: po.id,
    part_definition_id: part.id
  ) do |l|
    l.quantity = RECEIVED_PO_QUANTITY
    l.quantity_received = RECEIVED_PO_QUANTITY
    l.status = "RECEIVED"
  end
  unless line.status == "RECEIVED" && line.quantity == RECEIVED_PO_QUANTITY && line.quantity_received == RECEIVED_PO_QUANTITY
    line.update!(quantity: RECEIVED_PO_QUANTITY, quantity_received: RECEIVED_PO_QUANTITY, status: "RECEIVED")
  end
end

SeedHelper.step("seed #{RECEIVED_PO_QUANTITY} #{RECEIVED_PO_PART_NUMBER} instances + RECEIVED events") do
  part = definitions.fetch(RECEIVED_PO_PART_NUMBER)

  (1..RECEIVED_PO_QUANTITY).each do |n|
    serial = format("%s%04d", HORN_SERIAL_PREFIX, n)
    instance = PartInstance.find_or_create_by!(serial_number: serial) do |pi|
      pi.part_definition_id = part.id
      pi.current_status = "RECEIVED"
    end

    # Append-only log: write the RECEIVED event at most once per instance.
    unless instance.lifecycle_events.exists?(event_type: "RECEIVED")
      instance.lifecycle_events.create!(
        event_type: "RECEIVED",
        actor: "system/seed",
        occurred_at: Time.current,
        notes: "Received via #{RECEIVED_PO_SUPPLIER_ID} (Track 5 seed)."
      )
    end
  end
end

SeedHelper.step("set #{RECEIVED_PO_PART_NUMBER} stock quantity_on_hand = #{RECEIVED_PO_QUANTITY} (+ guarded audit log)") do
  part = definitions.fetch(RECEIVED_PO_PART_NUMBER)
  stock = Stock.find_or_create_by!(part_definition_id: part.id)
  stock.update!(quantity_on_hand: RECEIVED_PO_QUANTITY) unless stock.quantity_on_hand == RECEIVED_PO_QUANTITY

  # No StockAuditLog model on this branch — insert via sanitized SQL, guarded on
  # `reason` so re-seeding never writes a duplicate audit row.
  already_logged = ActiveRecord::Base.connection.select_value(
    ActiveRecord::Base.sanitize_sql_array(
      [ "SELECT 1 FROM stock_audit_logs WHERE part_definition_id = ? AND reason = ? LIMIT 1",
        part.id, HORN_STOCK_AUDIT_REASON ]
    )
  )

  unless already_logged
    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array(
        [ "INSERT INTO stock_audit_logs (part_definition_id, change_amount, reason) VALUES (?, ?, ?)",
          part.id, RECEIVED_PO_QUANTITY, HORN_STOCK_AUDIT_REASON ]
      )
    )
  end
end
