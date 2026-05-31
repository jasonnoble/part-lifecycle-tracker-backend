class BomExplosionJob < ApplicationJob
  queue_as :default

  # Enqueued once per customer order line on customer-order creation (JAS-41).
  #
  # Two-path BOM explosion for the line's part_definition and ordered quantity:
  #   1. Row-lock the Stock row; available = quantity_on_hand - quantity_reserved.
  #   2. In-stock portion = min(available, quantity): bump quantity_reserved and
  #      write a StockAuditLog (reuses the JAS-31/39 reservation pattern). The
  #      audit log doubles as the idempotency marker for this line's reservation.
  #   3. Shortfall = quantity - in_stock_portion (if > 0): create (or append to an
  #      existing open) SupplierPurchaseOrder line with NEEDS_ORDERING for the
  #      shortfall, linked to the customer order for traceability (JAS-30).
  #   4. Advance the CustomerOrder to IN_FULFILLMENT (idempotent via AASM guard).
  #
  # Idempotent: keyed off customer_order_line_id. Re-running does not double
  # reserve (StockAuditLog reason marker) nor duplicate the PO line (one
  # NEEDS_ORDERING line per customer_order + part_definition). See
  # BomExplosionService for the shared, transactional logic.
  #
  # Work-order creation: work_orders.part_instance_id is NOT NULL, but reserving
  # fungible stock does not pick a specific serialized instance, so a valid
  # WorkOrder cannot be created here. Per the JAS-42 AC we reserve + track
  # fulfillment via the customer-order-line-keyed StockAuditLog and defer
  # work-order creation until an instance is determinable (e.g. the JAS-35 flow).
  def perform(customer_order_line)
    BomExplosionService.new(customer_order_line).call
  end
end
