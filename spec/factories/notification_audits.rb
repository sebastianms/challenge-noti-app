# frozen_string_literal: true

FactoryBot.define do
  factory :notification_audit do
    correlation_id { SecureRandom.uuid }
    status         { "enqueued" }
    channel        { "email" }
    event_id       { nil }
    payload        { nil }
    metadata       { nil }

    trait :dispatched do
      status { "dispatched" }
    end

    trait :delivered do
      status { "delivered" }
    end

    trait :failed do
      status { "failed" }
    end
  end
end
