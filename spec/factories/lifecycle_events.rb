FactoryBot.define do
  factory :lifecycle_event do
    association :part_instance
    event_type { "RECEIVED" }
    actor { "system" }
    notes { nil }
    metadata { {} }
    occurred_at { Time.current }

    # A trait per event type (:received, :inspected, :in_assembly, :installed,
    # :validated, :certified, :ordered), kept in sync with the model constant.
    LifecycleEvent::EVENT_TYPES.each do |type|
      trait(type.downcase.to_sym) { event_type { type } }
    end
  end
end
