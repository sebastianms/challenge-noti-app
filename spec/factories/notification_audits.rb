# frozen_string_literal: true

FactoryBot.define do
  factory :notification_audit do
    correlation_id       { SecureRandom.uuid }
    status               { "enqueued" }
    channel              { "email" }
    source               { "internal" }
    recipient_canonical  { nil }
    event_id             { nil }
    payload              { nil }
    metadata             { nil }

    trait :dispatched do
      status { "dispatched" }
    end

    trait :delivered do
      status { "delivered" }
    end

    trait :failed do
      status { "failed" }
    end

    trait :from_webhook do
      source              { "sendgrid_webhook" }
      recipient_canonical { "user@example.com" }
    end

    trait :with_recipient do
      recipient_canonical { "recipient@example.com" }
    end
  end
end
