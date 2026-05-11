# frozen_string_literal: true

class RuleCache
  TTL = 5.minutes

  def self.fetch(notification_type)
    Rails.cache.fetch(cache_key(notification_type), expires_in: TTL) do
      NotificationRule.find_by(notification_type: notification_type, enabled: true)
    end
  end

  def self.invalidate(notification_type)
    Rails.cache.delete(cache_key(notification_type))
  end

  def self.clear_all
    Rails.cache.delete_matched("rule:*")
  end

  def self.cache_key(notification_type)
    "rule:#{notification_type}"
  end
end
