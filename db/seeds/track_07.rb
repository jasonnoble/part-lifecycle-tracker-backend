SeedHelper.track("Track 7 — Customer orders & BOM explosion results (JAS-44)")

# Track 7 seeds two customer orders that demonstrate both sides of the BOM
# explosion the worker (JAS-42) performs at runtime — but it builds the END
# STATE directly and idempotently rather than relying on the job:
#
#   CO-0001 "Powell Motors"      — 5x THE-HOMER-001, FULLY in stock.
#                                  5 units reserved, 5 part instances under
#                                  construction, 5 work orders linked back to
#                                  the customer order line. Status IN_FULFILLMENT.
#
#   CO-0002 "Springfield Taxi Co" — 20x THE-HOMER-001, PARTIALLY in stock.
#                                  10 reserved from on-hand stock; the 10-unit
#                                  shortfall becomes a supplier PO line with
#                                  status NEEDS_ORDERING. Status IN_FULFILLMENT.
#
# Reservation math: Powell reserves 5 + Springfield reserves 10 = 15 total. We
# set THE-HOMER-001 quantity_on_hand to 15 (absolutely, not incrementally) so
# the DB invariant quantity_reserved <= quantity_on_hand holds and so a full
# reseed — where Track 2 resets Homer stock to 0 — lands on the same numbers
# every time.

# NB: HOMER_PART_NUMBER is already defined by Track 3; reuse it rather than
# redefining (which warns "already initialized constant").
HOMER_ON_HAND       = 15  # covers both orders' reservations exactly
POWELL_QTY          = 5   # CO-0001, fully in stock
SPRINGFIELD_QTY     = 20  # CO-0002, 10 in stock + 10 to order
SPRINGFIELD_RESERVE = 10
SPRINGFIELD_SHORT   = SPRINGFIELD_QTY - SPRINGFIELD_RESERVE
TOTAL_RESERVED      = POWELL_QTY + SPRINGFIELD_RESERVE

homer = PartDefinition.find_or_create_by!(part_number: HOMER_PART_NUMBER) do |pd|
  pd.name        = "The Homer"
  pd.status      = "RELEASED"
  pd.revision    = "B"
  pd.description = "The everyman's car — every feature Homer ever wanted, all at once."
end

SeedHelper.step("set #{HOMER_PART_NUMBER} stock on_hand=#{HOMER_ON_HAND}, reserved=#{TOTAL_RESERVED}") do
  # Set absolutely so a full reseed (Track 2 zeroes Homer stock) is idempotent
  # and the reserved/on-hand invariant always holds.
  stock = Stock.find_or_initialize_by(part_definition_id: homer.id)
  stock.quantity_on_hand  = HOMER_ON_HAND
  stock.quantity_reserved = TOTAL_RESERVED
  stock.save!
end

SeedHelper.step("audit-log the #{TOTAL_RESERVED}-unit reservation (write-once)") do
  # StockAuditLog is append-only with no natural unique key; guard on reason so
  # repeated seeds never append a duplicate row.
  reason = "Track 7 seed: reserved #{TOTAL_RESERVED} for CO-0001 + CO-0002"
  unless StockAuditLog.exists?(part_definition_id: homer.id, reason: reason)
    StockAuditLog.create!(part_definition_id: homer.id, change_amount: TOTAL_RESERVED, reason: reason)
  end
end

# ---------------------------------------------------------------------------
# CO-0001 "Powell Motors" — 5x THE-HOMER-001, fully in stock, work orders built
# ---------------------------------------------------------------------------
SeedHelper.step("CO-0001 Powell Motors — #{POWELL_QTY}x #{HOMER_PART_NUMBER} (in stock)") do
  order = CustomerOrder.find_or_create_by!(customer_name: "Powell Motors")
  order.update!(status: "IN_FULFILLMENT") unless order.status == "IN_FULFILLMENT"

  line = CustomerOrderLine.find_or_create_by!(customer_order_id: order.id,
                                              part_definition_id: homer.id) do |l|
    l.quantity = POWELL_QTY
  end
  line.update!(quantity: POWELL_QTY) unless line.quantity == POWELL_QTY

  # One part instance + work order per reserved unit, each work order linked
  # back to the customer order line for demand->build traceability.
  (1..POWELL_QTY).each do |n|
    serial = format("HOMER-CO0001-%03d", n)
    instance = PartInstance.find_or_create_by!(serial_number: serial) do |pi|
      pi.part_definition_id = homer.id
      pi.current_status     = "IN_ASSEMBLY"
    end

    WorkOrder.find_or_create_by!(customer_order_line_id: line.id,
                                 part_instance_id: instance.id) do |wo|
      wo.part_definition_id = homer.id
      wo.status             = "OPEN"
    end
  end
end

# ---------------------------------------------------------------------------
# CO-0002 "Springfield Taxi Co" — 20x THE-HOMER-001, partial: 10 reserved,
# 10 need ordering via a supplier PO line.
# ---------------------------------------------------------------------------
SeedHelper.step("CO-0002 Springfield Taxi Co — #{SPRINGFIELD_QTY}x #{HOMER_PART_NUMBER} (#{SPRINGFIELD_RESERVE} in stock, #{SPRINGFIELD_SHORT} to order)") do
  order = CustomerOrder.find_or_create_by!(customer_name: "Springfield Taxi Co")
  order.update!(status: "IN_FULFILLMENT") unless order.status == "IN_FULFILLMENT"

  line = CustomerOrderLine.find_or_create_by!(customer_order_id: order.id,
                                              part_definition_id: homer.id) do |l|
    l.quantity = SPRINGFIELD_QTY
  end
  line.update!(quantity: SPRINGFIELD_QTY) unless line.quantity == SPRINGFIELD_QTY

  # The shortfall becomes a supplier PO tied to this customer order, with a
  # NEEDS_ORDERING line for the units we couldn't reserve from stock.
  po = SupplierPurchaseOrder.find_or_create_by!(customer_order_id: order.id,
                                                supplier_id: "ACME-PARTS") do |spo|
    spo.status = "OPEN"
  end

  po_line = SupplierPurchaseOrderLine.find_or_create_by!(supplier_purchase_order_id: po.id,
                                                         part_definition_id: homer.id) do |pol|
    pol.quantity = SPRINGFIELD_SHORT
    pol.status   = "NEEDS_ORDERING"
  end
  po_line.update!(quantity: SPRINGFIELD_SHORT) unless po_line.quantity == SPRINGFIELD_SHORT
  po_line.update!(status: "NEEDS_ORDERING")     unless po_line.status == "NEEDS_ORDERING"
end
