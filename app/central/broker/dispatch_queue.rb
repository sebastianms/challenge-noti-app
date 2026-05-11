# frozen_string_literal: true

class DispatchQueue < ApplicationRecord
  self.table_name = "dispatch_queue"

  BACKOFF_SCHEDULE = [ 1.minute, 5.minutes, 25.minutes ].freeze
  MAX_ATTEMPTS     = BACKOFF_SCHEDULE.size

  validates :event_id,        presence: true
  validates :priority,        inclusion: { in: %w[critical standard bulk] }
  validates :status,          inclusion: { in: %w[pending in_flight done failed] }
  validates :attempts,        numericality: { greater_than_or_equal_to: 0 }
  validates :next_attempt_at, presence: true

  def next_backoff
    BACKOFF_SCHEDULE[attempts] || BACKOFF_SCHEDULE.last
  end

  def permanent_failure?
    attempts >= MAX_ATTEMPTS
  end
end
