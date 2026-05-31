class BomItemSerializer
  include Alba::Resource

  transform_keys :lower_camel

  attributes :id, :quantity

  attribute(:child_part_number) { |item| item.child.part_number }
  attribute(:child_part_name) { |item| item.child.name }

  attribute :deleted_at do |item|
    item.deleted_at&.utc&.iso8601(3)
  end

  attribute :dependencies do |item|
    item.prerequisite_links.map do |link|
      {
        prerequisiteBomItemId: link.prerequisite_bom_item_id,
        prerequisitePartNumber: link.prerequisite.child.part_number
      }
    end
  end
end
