# frozen_string_literal: true

class PendingDigest < ApplicationRecord
  validates :notification_type,   presence: true
  validates :recipient_canonical, presence: true
  validates :correlation_id,      presence: true
  validates :event_id,            presence: true
  validates :status, inclusion: { in: %w[pending consolidating consolidated orphaned] }
end
