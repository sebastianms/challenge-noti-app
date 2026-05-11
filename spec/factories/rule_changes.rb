# frozen_string_literal: true

FactoryBot.define do
  factory :rule_change do
    association :admin_user
    association :notification_rule
    action { "created" }
    add_attribute(:before) { nil }
    add_attribute(:after)  { { "notification_type" => "birthday", "enabled" => true } }

    trait :created do
      action { "created" }
      add_attribute(:before) { nil }
      add_attribute(:after)  { { "notification_type" => "birthday", "enabled" => true } }
    end

    trait :updated do
      action { "updated" }
      add_attribute(:before) { { "max_per_day" => 1 } }
      add_attribute(:after)  { { "max_per_day" => 2 } }
    end

    trait :deleted do
      notification_rule { nil }
      action { "deleted" }
      add_attribute(:before) { { "notification_type" => "birthday", "enabled" => true } }
      add_attribute(:after)  { nil }
    end
  end
end
