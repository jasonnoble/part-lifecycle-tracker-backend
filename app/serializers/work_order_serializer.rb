class WorkOrderSerializer
  include Alba::Resource

  transform_keys :lower_camel

  attributes :id, :status, :customer_order_line_id

  attribute(:part_number) { |wo| wo.part_definition.part_number }
  attribute(:serial_number) { |wo| wo.part_instance.serial_number }

  has_many :work_order_steps, key: :steps, resource: WorkOrderStepSerializer

  attribute(:created_at) { |wo| wo.created_at&.utc&.iso8601(3) }
  attribute(:updated_at) { |wo| wo.updated_at&.utc&.iso8601(3) }
end
