# frozen_string_literal: true

class RulesEngine
  def self.decide(event:)
    rule = RuleCache.fetch(event.notification_type)
    return Decision.dispatch if rule.nil?

    return Decision.filter(reason: "disabled",     rule_id: rule.id) if channel_blocked?(rule)
    return Decision.filter(reason: "rate_limited", rule_id: rule.id) if RateLimitEvaluator.exceeded?(rule, event)
    return Decision.filter(reason: "cooldown",     rule_id: rule.id) if CooldownEvaluator.in_cooldown?(rule, event)
    return Decision.digest(rule_id: rule.id, window: rule.digest_window_seconds) if rule.digest_window_seconds.present?

    Decision.dispatch(rule_id: rule.id, priority: rule.priority)
  end

  def self.channel_blocked?(rule)
    rule.channels.is_a?(Array) && rule.channels.empty?
  end
  private_class_method :channel_blocked?
end
