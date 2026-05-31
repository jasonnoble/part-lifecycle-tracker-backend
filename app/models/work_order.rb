class WorkOrder < ApplicationRecord
  include AASM

  STATUSES = %w[OPEN BLOCKED COMPLETE].freeze

  belongs_to :part_definition
  belongs_to :part_instance

  # Stable ordering so serialized `steps` (and the generated OpenAPI example) are
  # deterministic regardless of insertion/return order.
  has_many :work_order_steps, -> { order(:created_at, :id) }, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }

  scope :by_status, ->(status) { where(status: status) }

  # State names are intentionally UPPERCASE so they match the values persisted in
  # the `status` column (enforced by the work_orders_status_check constraint).
  # AASM persists the state *name* verbatim and reads it back with `to_sym`, so
  # the name must equal the stored string (no value-mapping in this version). See
  # PartDefinition for the canonical pattern. The block/complete transition
  # endpoints land in JAS-36/JAS-37; the machine lives here as the single source
  # of truth and is defined now so later stories can reuse the events.
  aasm column: :status, whiny_transitions: false do
    state :OPEN, initial: true
    state :BLOCKED
    state :COMPLETE

    event :block do
      transitions from: %i[OPEN BLOCKED], to: :BLOCKED
    end

    event :unblock do
      transitions from: %i[BLOCKED OPEN], to: :OPEN
    end

    event :complete do
      transitions from: %i[OPEN BLOCKED], to: :COMPLETE
    end
  end
end
