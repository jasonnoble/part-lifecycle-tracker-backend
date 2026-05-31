class SupplierPurchaseOrder < ApplicationRecord
  include AASM

  STATUSES = %w[OPEN PARTIALLY_RECEIVED RECEIVED CLOSED].freeze

  has_many :supplier_purchase_order_lines, dependent: :destroy
  belongs_to :customer_order, optional: true

  validates :supplier_id, presence: true
  validates :status, inclusion: { in: STATUSES }

  # State names are intentionally UPPERCASE so they match the values persisted in
  # the `status` column (enforced by the supplier_purchase_orders_status_check
  # constraint). AASM persists the state *name* verbatim and reads it back with
  # `to_sym`, so the name must equal the stored string (no value-mapping in this
  # version). See PartDefinition for the canonical pattern. The receive/close
  # transition endpoints land in JAS-31; the machine lives here as the single
  # source of truth.
  aasm column: :status, whiny_transitions: false do
    state :OPEN, initial: true
    state :PARTIALLY_RECEIVED
    state :RECEIVED
    state :CLOSED

    event :partially_receive do
      transitions from: %i[OPEN PARTIALLY_RECEIVED], to: :PARTIALLY_RECEIVED
    end

    event :receive do
      transitions from: %i[OPEN PARTIALLY_RECEIVED], to: :RECEIVED
    end

    event :close do
      transitions from: :RECEIVED, to: :CLOSED
    end
  end
end
