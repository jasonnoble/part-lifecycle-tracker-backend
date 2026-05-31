class WorkOrderStep < ApplicationRecord
  include AASM

  STATUSES = %w[PENDING INSTALLED VALIDATED CERTIFIED BLOCKED].freeze

  belongs_to :work_order
  belongs_to :bom_item
  belongs_to :installed_part_instance,
    class_name: "PartInstance",
    foreign_key: :installed_part_instance_id,
    optional: true

  validates :status, inclusion: { in: STATUSES }

  # State names are intentionally UPPERCASE so they match the values persisted in
  # the `status` column (enforced by the work_order_steps_status_check
  # constraint). AASM persists the state *name* verbatim and reads it back with
  # `to_sym`, so the name must equal the stored string (no value-mapping in this
  # version). See PartDefinition for the canonical pattern. The install/validate/
  # certify transition endpoints land in JAS-36; the stock reservation BLOCKED
  # transition lands in JAS-39. The machine lives here as the single source of
  # truth and is defined now so later stories can reuse the events.
  aasm column: :status, whiny_transitions: false do
    state :PENDING, initial: true
    state :INSTALLED
    state :VALIDATED
    state :CERTIFIED
    state :BLOCKED

    event :install do
      transitions from: :PENDING, to: :INSTALLED
    end

    event :validate_step do
      transitions from: :INSTALLED, to: :VALIDATED
    end

    event :certify do
      transitions from: :VALIDATED, to: :CERTIFIED
    end

    event :block do
      transitions from: %i[PENDING BLOCKED], to: :BLOCKED
    end

    event :unblock do
      transitions from: %i[BLOCKED PENDING], to: :PENDING
    end
  end
end
