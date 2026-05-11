# frozen_string_literal: true

class NotificationRule < ApplicationRecord
  validates :notification_type, presence: true, uniqueness: true
  validates :priority, inclusion: { in: %w[critical standard bulk], allow_nil: true }
  validates :max_per_day,           numericality: { greater_than: 0, allow_nil: true }
  validates :cooldown_seconds,      numericality: { greater_than: 0, allow_nil: true }
  validates :digest_window_seconds, numericality: { greater_than: 0, allow_nil: true }

  after_save    { RuleCache.invalidate(notification_type) }
  after_destroy { RuleCache.invalidate(notification_type) }

  scope :active, -> { where(enabled: true) }
end
