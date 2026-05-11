# frozen_string_literal: true

FactoryBot.define do
  factory :notification_rule do
    sequence(:notification_type) { |n| "type_#{n}" }
    channels                     { [ "email" ] }
    max_per_day                  { nil }
    cooldown_seconds             { nil }
    digest_window_seconds        { nil }
    priority                     { nil }
    enabled                      { true }

    trait :with_rate_limit do
      max_per_day { 3 }
    end

    trait :with_cooldown do
      cooldown_seconds { 60 }
    end

    trait :with_digest do
      digest_window_seconds { 300 }
    end

    trait :disabled_channel do
      channels { [] }
    end

    trait :disabled do
      enabled { false }
    end
  end
end
