class StockReservationJob < ApplicationJob
  queue_as :default

  # Enqueued on work order creation (JAS-35). For each PENDING work order step we
  # reserve one unit of the step's required part (the BOM item's child). The
  # planning doc (track-06) and JAS-39 both specify a per-step reservation of 1:
  #
  #   available = quantity_on_hand - quantity_reserved
  #   available >= 1 -> increment quantity_reserved, step stays PENDING
  #   available <  1 -> block the step (status BLOCKED)
  #
  # Atomicity: the stocks row is row-locked (SELECT ... FOR UPDATE) inside a
  # transaction before we read availability and write the reservation, so two
  # concurrent runs cannot both reserve the last unit.
  #
  # Idempotency: each successful reservation writes a StockAuditLog whose reason
  # is keyed to the step id. Before reserving we skip any step that already has
  # such a log, so re-running the job never double-reserves. Already-BLOCKED
  # steps (no longer PENDING) are likewise skipped.
  def perform(work_order)
    blocked_any = false

    work_order.work_order_steps.where(status: "PENDING").find_each do |step|
      blocked_any = true unless reserve_for(step)
    end

    work_order.block! if blocked_any && work_order.may_block?
  end

  private

  # Returns true if the step is (or was already) reserved, false if it had to be
  # blocked for insufficient stock.
  def reserve_for(step)
    part = step.bom_item.child
    reason = reservation_reason(step)

    Stock.transaction do
      return true if StockAuditLog.exists?(part_definition: part, reason: reason)

      stock = Stock.lock.find_or_create_by!(part_definition: part)
      available = stock.quantity_on_hand - stock.quantity_reserved

      if available >= 1
        stock.update!(quantity_reserved: stock.quantity_reserved + 1)
        StockAuditLog.create!(part_definition: part, change_amount: -1, reason: reason)
        true
      else
        step.block! if step.may_block?
        false
      end
    end
  end

  def reservation_reason(step)
    "Reserved for work order step #{step.id}"
  end
end
