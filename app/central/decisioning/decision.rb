# frozen_string_literal: true

class Decision
  attr_reader :kind, :reason, :rule_id, :digest_window_seconds, :priority

  def self.dispatch(rule_id: nil, priority: nil)
    new(:dispatch, rule_id: rule_id, priority: priority)
  end

  def self.digest(rule_id:, window:)
    new(:digest, rule_id: rule_id, digest_window_seconds: window)
  end

  def self.filter(reason:, rule_id:)
    new(:filter, reason: reason, rule_id: rule_id)
  end

  def initialize(kind, reason: nil, rule_id: nil, digest_window_seconds: nil, priority: nil)
    @kind                  = kind
    @reason                = reason
    @rule_id               = rule_id
    @digest_window_seconds = digest_window_seconds
    @priority              = priority
  end

  def dispatch? = @kind == :dispatch
  def digest?   = @kind == :digest
  def filter?   = @kind == :filter
end
