class PartInstance < ApplicationRecord
  # Shared with LifecycleEvent — the 7 lifecycle event/status values, enforced by
  # DB check constraints on both part_instances.current_status and
  # lifecycle_events.event_type.
  STATUSES = %w[ORDERED RECEIVED INSPECTED IN_ASSEMBLY INSTALLED VALIDATED CERTIFIED].freeze

  belongs_to :part_definition
  has_many :lifecycle_events, dependent: :destroy

  validates :serial_number, presence: true, uniqueness: true
  validates :current_status, inclusion: { in: STATUSES }

  scope :for_part_number, ->(part_number) {
    joins(:part_definition).where(part_definitions: { part_number: part_number })
  }
  scope :with_status, ->(status) { where(current_status: status) }
end
