class StockReservationJob < ApplicationJob
  queue_as :default

  # Enqueued on work order creation (JAS-35). Body is intentionally empty for now.
  # TODO(JAS-39): reserve stock / set steps BLOCKED. For each PENDING step,
  # row-lock the relevant stock, reserve 1 if available (quantity_on_hand -
  # quantity_reserved >= 1) or transition the step to BLOCKED if not. Must be
  # idempotent so re-running does not double-reserve.
  def perform(work_order)
  end
end
