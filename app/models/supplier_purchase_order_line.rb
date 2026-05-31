class SupplierPurchaseOrderLine < ApplicationRecord
  include AASM

  STATUSES = %w[NEEDS_ORDERING ORDERED PARTIALLY_RECEIVED RECEIVED].freeze

  belongs_to :supplier_purchase_order
  belongs_to :part_definition

  validates :quantity, numericality: { greater_than: 0, only_integer: true }
  validates :quantity_received, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :status, inclusion: { in: STATUSES }

  # UPPERCASE state names match the persisted `status` column values (enforced by
  # supplier_purchase_order_lines_status_check). See PartDefinition / the note on
  # SupplierPurchaseOrder for why no value-mapping is used.
  aasm column: :status, whiny_transitions: false do
    state :NEEDS_ORDERING, initial: true
    state :ORDERED
    state :PARTIALLY_RECEIVED
    state :RECEIVED

    event :order do
      transitions from: :NEEDS_ORDERING, to: :ORDERED
    end

    event :partially_receive do
      transitions from: %i[NEEDS_ORDERING ORDERED PARTIALLY_RECEIVED], to: :PARTIALLY_RECEIVED
    end

    event :receive do
      transitions from: %i[NEEDS_ORDERING ORDERED PARTIALLY_RECEIVED], to: :RECEIVED
    end
  end
end
