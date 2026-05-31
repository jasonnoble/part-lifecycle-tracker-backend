class LifecycleEvent < ApplicationRecord
  # Append-only event log. Rows are never updated or deleted; there is no
  # updated_at column. event_type is constrained to PartInstance::STATUSES both
  # here and by the lifecycle_events_event_type_check DB constraint.
  EVENT_TYPES = PartInstance::STATUSES

  belongs_to :part_instance

  validates :event_type, inclusion: { in: EVENT_TYPES }
  validates :actor, presence: true
  validates :occurred_at, presence: true

  # Deterministic ordering for stable Pagy pages: occurred_at is neither unique
  # nor monotonic (backdated events, ties), so id breaks ties.
  scope :chronological, -> { order(:occurred_at, :id) }
end
