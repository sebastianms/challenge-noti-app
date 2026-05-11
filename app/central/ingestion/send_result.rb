# frozen_string_literal: true

class SendResult
  STATES = %i[created duplicate rejected filtered].freeze

  attr_reader :state, :correlation_id, :reason

  def initialize(state:, correlation_id: nil, reason: nil)
    raise ArgumentError, "invalid state: #{state}" unless STATES.include?(state)

    @state = state
    @correlation_id = correlation_id
    @reason = reason
    freeze
  end

  def self.created(correlation_id:)
    new(state: :created, correlation_id: correlation_id)
  end

  def self.duplicate(correlation_id:)
    new(state: :duplicate, correlation_id: correlation_id)
  end

  def self.rejected(reason:)
    new(state: :rejected, reason: reason)
  end

  def self.filtered(correlation_id:, reason: "blacklisted")
    new(state: :filtered, correlation_id: correlation_id, reason: reason)
  end

  def created?   = state == :created
  def duplicate? = state == :duplicate
  def rejected?  = state == :rejected
  def filtered?  = state == :filtered
  def persisted? = created? || duplicate? || filtered?

  def to_h
    { state: state, correlation_id: correlation_id, reason: reason }.compact
  end
end
