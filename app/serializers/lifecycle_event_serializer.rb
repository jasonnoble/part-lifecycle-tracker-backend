class LifecycleEventSerializer
  include Alba::Resource

  transform_keys :lower_camel

  # No updatedAt — lifecycle events are append-only and never modified.
  attributes :id, :event_type, :actor, :notes, :metadata

  attribute :occurred_at do |event|
    event.occurred_at.utc.iso8601(3)
  end

  attribute :recorded_at do |event|
    event.recorded_at.utc.iso8601(3)
  end
end
