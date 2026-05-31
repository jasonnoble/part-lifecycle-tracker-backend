class BomExplosionJob < ApplicationJob
  queue_as :default

  # Enqueued once per customer order line on customer-order creation (JAS-41).
  # Body is intentionally empty for now.
  # TODO(JAS-42): explode BOM — for each line, calculate available stock
  # (quantity_on_hand - quantity_reserved), reserve what's available (row-locked,
  # write a StockAuditLog, reuse the JAS-31/39 reservation pattern) and enqueue
  # work order creation (JAS-35); for the shortfall, create/append a
  # SupplierPurchaseOrder line with NEEDS_ORDERING (JAS-30). Advance the customer
  # order to IN_FULFILLMENT once explosion completes. Must be idempotent.
  def perform(customer_order_line)
  end
end
