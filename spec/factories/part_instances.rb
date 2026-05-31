FactoryBot.define do
  factory :part_instance do
    association :part_definition
    sequence(:serial_number) { |n| "SN-#{format('%05d', n)}" }
    current_status { "RECEIVED" }
  end
end
