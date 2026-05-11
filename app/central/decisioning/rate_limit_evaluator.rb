# frozen_string_literal: true

class RateLimitEvaluator
  COUNTED_STATUSES = %w[enqueued dispatched delivered].freeze

  def self.exceeded?(rule, event)
    return false if rule.max_per_day.nil?

    count = NotificationAudit
      .where(notification_type: event.notification_type)
      .where(recipient_canonical: event.recipient_canonical)
      .where(status: COUNTED_STATUSES)
      .where("created_at >= ?", 24.hours.ago)
      .count

    count >= rule.max_per_day
  end
end
