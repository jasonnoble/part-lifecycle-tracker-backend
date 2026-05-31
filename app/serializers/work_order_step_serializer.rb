class WorkOrderStepSerializer
  include Alba::Resource

  transform_keys :lower_camel

  attributes :id, :bom_item_id, :status, :installed_part_instance_id,
             :installed_actor, :validated_actor, :certified_actor

  attribute(:child_part_number) { |step| step.bom_item.child.part_number }
  attribute(:child_part_name) { |step| step.bom_item.child.name }

  # These timestamps are nullable (a PENDING step has none yet). Guard with a
  # single nil-check via &.then so branch coverage sees both the present and
  # absent cases — a plain `&.utc&.iso8601` leaves a dead branch on the second
  # &. (Time#utc never returns nil).
  attribute(:installed_at) { |step| step.installed_at&.then { |t| t.utc.iso8601(3) } }
  attribute(:validated_at) { |step| step.validated_at&.then { |t| t.utc.iso8601(3) } }
  attribute(:certified_at) { |step| step.certified_at&.then { |t| t.utc.iso8601(3) } }
end
