# Builds the rich, self-contained snapshot served by GET
# /parts/:part_number/context (JAS-45). Designed to drop straight into an LLM
# prompt: one response answers "what is this part, how many exist and in what
# state, what's on order, what's in the BOM, and what just happened?".
#
# The `summary` is a deterministic TEMPLATED string — never LLM-generated — so
# the response is fast, reproducible, and safe to cache or diff.
#
# Returns camelCase keys directly (no alba) since the shape is bespoke and flat.
class PartContext
  STATUS_VERBS = {
    "RELEASED" => "released",
    "DRAFT" => "in draft",
    "OBSOLETE" => "obsolete"
  }.freeze

  # POs counted by openPurchaseOrders: not yet fully received/closed.
  OPEN_PO_STATUSES = %w[OPEN PARTIALLY_RECEIVED].freeze

  RECENT_EVENT_LIMIT = 5

  def initialize(part)
    @part = part
  end

  def as_json(*)
    {
      partNumber: @part.part_number,
      name: @part.name,
      revision: @part.revision,
      status: @part.status,
      summary: summary,
      inventory: { total: inventory_by_status.values.sum, byStatus: inventory_by_status },
      openPurchaseOrders: open_purchase_orders_count,
      bom: bom,
      recentEvents: recent_events,
      generatedAt: Time.current.utc.iso8601
    }
  end

  private

  # Aggregate instance counts in one GROUP BY (only statuses with >= 1 instance).
  # Perf: at scale an index on part_instances (part_definition_id, current_status)
  # would back this; tiny at demo scale, so not added (noted in the PR).
  def inventory_by_status
    @inventory_by_status ||=
      @part.part_instances.group(:current_status).count
  end

  def summary
    name = @part.name
    revision = @part.revision.presence || "—"
    verb = STATUS_VERBS.fetch(@part.status, @part.status.to_s.downcase)
    total = inventory_by_status.values.sum
    in_assembly = inventory_by_status.fetch("IN_ASSEMBLY", 0)
    certified = inventory_by_status.fetch("CERTIFIED", 0)

    "#{name}. Rev #{revision} #{verb}. " \
      "#{total} instances created, #{in_assembly} in assembly, #{certified} certified."
  end

  # Supplier POs in OPEN or PARTIALLY_RECEIVED that have a line for this part.
  def open_purchase_orders_count
    SupplierPurchaseOrder
      .where(status: OPEN_PO_STATUSES)
      .where(id: SupplierPurchaseOrderLine.where(part_definition_id: @part.id).select(:supplier_purchase_order_id))
      .count
  end

  # Active (non-soft-deleted) BOM items; stockAvailable = on_hand - reserved
  # (0 when the child has no stock row).
  def bom
    @part.bom_items
      .where(deleted_at: nil)
      .includes(child: :stock)
      .order(:created_at)
      .map do |item|
        child = item.child
        stock = child.stock
        available = stock ? stock.quantity_on_hand - stock.quantity_reserved : 0
        {
          partNumber: child.part_number,
          name: child.name,
          quantity: item.quantity,
          stockAvailable: available
        }
      end
  end

  # Last 5 lifecycle events across ALL instances of this part, newest first
  # (id breaks occurred_at ties deterministically).
  def recent_events
    LifecycleEvent
      .joins(:part_instance)
      .where(part_instances: { part_definition_id: @part.id })
      .order(occurred_at: :desc, id: :desc)
      .limit(RECENT_EVENT_LIMIT)
      .includes(:part_instance)
      .map do |event|
        {
          serialNumber: event.part_instance.serial_number,
          eventType: event.event_type,
          occurredAt: event.occurred_at.utc.iso8601,
          actor: event.actor,
          notes: event.notes
        }
      end
  end
end
