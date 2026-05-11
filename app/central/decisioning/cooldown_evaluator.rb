# frozen_string_literal: true

class CooldownEvaluator
  COUNTED_STATUSES = %w[enqueued dispatched delivered].freeze

  def self.in_cooldown?(rule, event)
    return false if rule.cooldown_seconds.nil?

    NotificationAudit
      .where(notification_type: event.notification_type)
      .where(recipient_canonical: event.recipient_canonical)
      .where(status: COUNTED_STATUSES)
      .where("created_at >= ?", rule.cooldown_seconds.seconds.ago)
      .exists?
  end
end
