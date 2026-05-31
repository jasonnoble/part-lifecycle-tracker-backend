class PartInstanceSerializer
  include Alba::Resource

  transform_keys :lower_camel

  attributes :id, :serial_number, :current_status

  attribute(:part_number) { |instance| instance.part_definition.part_number }

  attribute :created_at do |instance|
    instance.created_at.utc.iso8601(3)
  end

  attribute :updated_at do |instance|
    instance.updated_at.utc.iso8601(3)
  end
end
