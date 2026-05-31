class CustomerOrderLineSerializer
  include Alba::Resource

  transform_keys :lower_camel

  attributes :id, :quantity

  attribute(:part_number) { |line| line.part_definition.part_number }
  attribute(:part_name) { |line| line.part_definition.name }
end
