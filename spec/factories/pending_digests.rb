# frozen_string_literal: true

FactoryBot.define do
  factory :pending_digest do
    notification_type   { "welcome" }
    recipient_canonical { "user@example.com" }
    correlation_id      { SecureRandom.uuid }
    event_id            { 1 }
    payload             { { "context" => { "name" => "Juan" } } }
    rule_snapshot       { { "rule_id" => 1, "digest_window_seconds" => 60 } }
    dispatch_at         { 1.minute.from_now }
    status              { "pending" }

    trait :ready do
      dispatch_at { 5.minutes.ago }
    end

    trait :future do
      dispatch_at { 1.hour.from_now }
    end

    trait :consolidated do
      status            { "consolidated" }
      consolidated_into { SecureRandom.uuid }
    end
  end
end
