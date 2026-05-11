# frozen_string_literal: true

FactoryBot.define do
  factory :notification_blacklist do
    sequence(:recipient_canonical) { |n| "blocked#{n}@example.com" }
    scope  { "global" }
    target { nil }
    source { "manual" }
    reason { "user requested unsubscribe" }

    trait :global do
      scope  { "global" }
      target { nil }
    end

    trait :type_scoped do
      scope  { "type" }
      target { "birthday" }
    end

    trait :channel_scoped do
      scope  { "channel" }
      target { "email" }
    end

    trait :hard_bounce do
      scope  { "channel" }
      target { "email" }
      source { "hard_bounce" }
      reason { "550 5.1.1 mailbox does not exist" }
    end
  end
end
