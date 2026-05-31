FactoryBot.define do
  factory :bom_item_dependency do
    association :prerequisite, factory: :bom_item
    association :dependent, factory: :bom_item
  end
end
