class BomExplosionJob < ApplicationJob
  queue_as :default

  # Enqueued once per customer order line on customer-order creation (JAS-41).
  # All logic lives in BomExplosionService — see there for the algorithm and
  # idempotency guarantees.
  def perform(customer_order_line)
    BomExplosionService.new(customer_order_line).call
  end
end
