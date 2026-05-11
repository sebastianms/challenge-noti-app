# frozen_string_literal: true

FactoryBot.define do
  factory :admin_user do
    sequence(:email) { |n| "admin#{n}@noti-central.local" }
    password              { "Admin12345678!" }
    password_confirmation { "Admin12345678!" }
    role { "admin" }

    trait :admin       do role { "admin" } end
    trait :product     do role { "product" } end
    trait :support     do role { "support" } end
    trait :engineering do role { "engineering" } end
  end
end
