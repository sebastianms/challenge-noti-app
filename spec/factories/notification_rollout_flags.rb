# frozen_string_literal: true

FactoryBot.define do
  factory :notification_rollout_flag do
    sequence(:notification_type) { |n| "notification_type_#{n}" }
    team_name { "Equipo de prueba" }
    enrolled  { true }
    notes     { nil }
  end
end
