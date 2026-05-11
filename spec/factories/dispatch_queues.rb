# frozen_string_literal: true

FactoryBot.define do
  factory :dispatch_queue do
    event_id        { 1 }
    priority        { "standard" }
    status          { "pending" }
    attempts        { 0 }
    next_attempt_at { Time.current }

    trait :in_flight do
      status    { "in_flight" }
      locked_at { Time.current }
    end

    trait :failed do
      status        { "failed" }
      attempts      { DispatchQueue::MAX_ATTEMPTS }
      failed_reason { "sendgrid_5xx: 503" }
    end

    trait :done do
      status   { "done" }
      attempts { 1 }
    end
  end
end
