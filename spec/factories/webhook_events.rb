# frozen_string_literal: true

FactoryBot.define do
  factory :webhook_event do
    source       { "sendgrid" }
    payload      { [ { "event" => "delivered", "email" => "user@example.com", "timestamp" => Time.current.to_i } ] }
    signature    { "test_signature" }
    signature_ts { Time.current.to_i.to_s }
    status       { "pending" }
    received_at  { Time.current }
    attempts     { 0 }

    trait :processing do
      status    { "processing" }
      locked_at { Time.current }
    end

    trait :processed do
      status       { "processed" }
      processed_at { Time.current }
    end

    trait :failed do
      status        { "failed" }
      failed_reason { "SendgridSignature::InvalidSignature" }
      attempts      { 3 }
    end
  end
end
