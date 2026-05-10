# frozen_string_literal: true

FactoryBot.define do
  factory :notification_event do
    notification_type     { "password_reset" }
    recipient_canonical   { "user@example.com" }
    recipient_type        { "email" }
    context_id            { SecureRandom.uuid }
    payload               { { subject: "Reset your password" } }
    idempotency_window_ts { Time.current.utc.beginning_of_minute }
    idempotency_hash do
      Digest::SHA256.hexdigest(
        "#{notification_type}|#{recipient_canonical}|#{context_id}|#{idempotency_window_ts.iso8601}"
      )
    end
    status { "pending" }

    trait :sent do
      status { "sent" }
    end

    trait :rejected do
      status { "rejected" }
    end

    trait :failed do
      status { "failed" }
    end

    trait :user_id_recipient do
      recipient_type      { "user_id" }
      recipient_canonical { "usr_#{SecureRandom.hex(4)}" }
    end
  end
end
