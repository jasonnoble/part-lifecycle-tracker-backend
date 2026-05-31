FactoryBot.define do
  factory :lifecycle_event do
    association :part_instance
    event_type { "RECEIVED" }
    actor { "system" }
    notes { nil }
    metadata { {} }
    occurred_at { Time.current }
  end
end
