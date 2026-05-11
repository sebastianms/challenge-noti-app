# frozen_string_literal: true

class BlacklistEvaluator
  SCOPE_PREDICATE = <<~SQL.squish.freeze
    scope = 'global'
    OR (scope = 'type'    AND target = ?)
    OR (scope = 'channel' AND target = ?)
  SQL

  def self.match(event:, channel: "email")
    recipient = event.recipient_canonical
    return nil if recipient.blank?

    NotificationBlacklist
      .where(recipient_canonical: recipient)
      .where(SCOPE_PREDICATE, event.notification_type, channel)
      .limit(1)
      .first
  end

  def self.blacklisted?(event:, channel: "email")
    !match(event: event, channel: channel).nil?
  end
end
