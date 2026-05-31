# Two-path BOM explosion for a single customer order line.
#
# Reserves available stock and raises a supplier PO line for any shortfall, then
# advances the parent customer order to IN_FULFILLMENT. Extracted from
# BomExplosionJob so the logic can be exercised synchronously in specs and
# reused if a synchronous explosion path is ever needed.
#
# Atomic per stock row (SELECT ... FOR UPDATE row-lock) and idempotent: a re-run
# neither double-reserves nor duplicates the PO line.
#   - Reservation idempotency: a StockAuditLog row whose reason is the stable
#     per-line marker (reserve_reason) signals the reservation already happened.
#   - PO-line idempotency: at most one open NEEDS_ORDERING line per
#     customer_order + part_definition; a re-run finds and leaves it alone.
class BomExplosionService
  def initialize(customer_order_line)
    @line = customer_order_line
    @part = customer_order_line.part_definition
    @customer_order = customer_order_line.customer_order
    @quantity = customer_order_line.quantity
  end

  def call
    ActiveRecord::Base.transaction do
      in_stock_portion = reserve_available_stock
      shortfall = @quantity - in_stock_portion
      raise_supplier_po_line(shortfall) if shortfall.positive?
      @customer_order.begin_fulfillment! unless @customer_order.IN_FULFILLMENT? || @customer_order.COMPLETE?
    end
  end

  private

  # Returns the quantity reserved on this run (0 if already reserved or none
  # available). Row-locks the stock row so concurrent explosions serialize.
  def reserve_available_stock
    stock = Stock.lock.find_or_create_by!(part_definition: @part)

    return already_reserved_amount if reserved?

    available = stock.quantity_on_hand - stock.quantity_reserved
    in_stock_portion = [ available, @quantity ].min
    return 0 unless in_stock_portion.positive?

    stock.update!(quantity_reserved: stock.quantity_reserved + in_stock_portion)
    StockAuditLog.create!(
      part_definition: @part,
      change_amount: in_stock_portion,
      reason: reserve_reason
    )
    in_stock_portion
  end

  # Idempotency marker for this line's reservation — re-running finds this log
  # and skips re-reserving. On a re-run we return the amount it recorded so the
  # shortfall (and therefore the existing PO line) is recomputed identically.
  def reserved?
    StockAuditLog.exists?(part_definition: @part, reason: reserve_reason)
  end

  def already_reserved_amount
    StockAuditLog.where(part_definition: @part, reason: reserve_reason).sum(:change_amount)
  end

  def reserve_reason
    "CO line reserve #{@line.id}"
  end

  # Create the shortfall PO line, or append it to this customer order's existing
  # open supplier PO. Idempotent: skip if a NEEDS_ORDERING line already exists
  # for this customer_order + part_definition.
  def raise_supplier_po_line(shortfall)
    po = open_supplier_po_for_customer_order
    return if po&.supplier_purchase_order_lines&.exists?(part_definition: @part, status: "NEEDS_ORDERING")

    po ||= SupplierPurchaseOrder.create!(
      supplier_id: "TBD",
      status: "OPEN",
      customer_order: @customer_order
    )
    po.supplier_purchase_order_lines.create!(
      part_definition: @part,
      quantity: shortfall,
      quantity_received: 0,
      status: "NEEDS_ORDERING"
    )
  end

  def open_supplier_po_for_customer_order
    SupplierPurchaseOrder
      .where(customer_order: @customer_order, status: "OPEN")
      .order(:created_at, :id)
      .first
  end
end
