# frozen_string_literal: true

FactoryBot.define do
  factory :notification_template do
    notification_type { "birthday" }
    locale            { "es" }
    title             { "¡Feliz cumpleaños, {{name}}!" }
    body              { "Hoy es tu día." }
    digest_template   { nil }
  end
end
