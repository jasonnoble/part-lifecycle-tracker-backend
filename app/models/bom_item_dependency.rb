class BomItemDependency < ApplicationRecord
  belongs_to :prerequisite, class_name: "BomItem", foreign_key: :prerequisite_bom_item_id
  belongs_to :dependent, class_name: "BomItem", foreign_key: :dependent_bom_item_id
end
