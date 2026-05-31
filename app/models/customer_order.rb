class CustomerOrder < ApplicationRecord
  include AASM

  STATUSES = %w[OPEN IN_FULFILLMENT COMPLETE].freeze

  # Stable ordering so serialized `lines` (and the generated OpenAPI example) are
  # deterministic regardless of insertion/return order.
  has_many :customer_order_lines, -> { order(:created_at, :id) }, dependent: :destroy

  validates :customer_name, presence: true
  validates :status, inclusion: { in: STATUSES }

  # State names are intentionally UPPERCASE so they match the values persisted in
  # the `status` column (enforced by the customer_orders_status_check constraint).
  # AASM persists the state *name* verbatim and reads it back with `to_sym`, so the
  # name must equal the stored string (no value-mapping in this version). See
  # PartDefinition/SupplierPurchaseOrder for the canonical pattern. The BOM explosion
  # worker (JAS-42) drives the begin_fulfillment/complete transitions; the machine
  # lives here as the single source of truth.
  aasm column: :status, whiny_transitions: false do
    state :OPEN, initial: true
    state :IN_FULFILLMENT
    state :COMPLETE

    event :begin_fulfillment do
      transitions from: %i[OPEN IN_FULFILLMENT], to: :IN_FULFILLMENT
    end

    event :complete do
      transitions from: %i[OPEN IN_FULFILLMENT], to: :COMPLETE
    end
  end
end
