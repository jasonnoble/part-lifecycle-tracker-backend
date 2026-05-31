class TestRecordSerializer
  include Alba::Resource

  transform_keys :lower_camel

  # No updatedAt — test records are append-only and never modified.
  attributes :id, :test_type, :result, :notes, :conducted_by

  attribute :occurred_at do |record|
    record.occurred_at.utc.iso8601(3)
  end

  attribute :recorded_at do |record|
    record.recorded_at.utc.iso8601(3)
  end
end
