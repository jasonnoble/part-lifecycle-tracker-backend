class WorkOrderStepSerializer
  include Alba::Resource

  transform_keys :lower_camel

  attributes :id, :bom_item_id, :status, :installed_part_instance_id,
             :installed_actor, :validated_actor, :certified_actor

  attribute(:child_part_number) { |step| step.bom_item.child.part_number }
  attribute(:child_part_name) { |step| step.bom_item.child.name }

  attribute(:installed_at) { |step| step.installed_at&.utc&.iso8601(3) }
  attribute(:validated_at) { |step| step.validated_at&.utc&.iso8601(3) }
  attribute(:certified_at) { |step| step.certified_at&.utc&.iso8601(3) }
end
