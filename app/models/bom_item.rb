class BomItem < ApplicationRecord
  belongs_to :parent, class_name: "PartDefinition", foreign_key: :parent_part_definition_id
  belongs_to :child, class_name: "PartDefinition", foreign_key: :child_part_definition_id
  has_many :bom_item_dependencies, foreign_key: :dependent_bom_item_id
end
