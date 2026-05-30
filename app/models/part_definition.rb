class PartDefinition < ApplicationRecord
  has_many :bom_items, foreign_key: :parent_part_definition_id, dependent: :destroy
  has_one :stock, dependent: :destroy
end
