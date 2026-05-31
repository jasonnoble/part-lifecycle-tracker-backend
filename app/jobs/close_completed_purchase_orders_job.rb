# Background worker that closes Supplier POs whose receiving is complete.
#
# A PO reaches RECEIVED once all of its lines are received (handled by the
# receive endpoint, JAS-31). This worker is the final, idempotent step: it
# transitions every RECEIVED PO to CLOSED via the AASM `close` event.
#
# Idempotency: it only ever scopes to RECEIVED POs, so already-CLOSED POs are
# skipped naturally and re-running is safe.
class CloseCompletedPurchaseOrdersJob < ApplicationJob
  queue_as :default

  def perform
    closed_count = 0

    SupplierPurchaseOrder.where(status: "RECEIVED").find_each do |po|
      # `close` is a no-op (returns false) for any PO not in RECEIVED thanks to
      # whiny_transitions: false, but the scope above already guarantees state.
      closed_count += 1 if po.close && po.save

      # TODO (Track 6/7): trigger work order creation for linked
      # customer_order_lines once the work-order side exists.
    end

    Rails.logger.info("CloseCompletedPurchaseOrdersJob closed #{closed_count} supplier PO(s)")
    closed_count
  end
end
