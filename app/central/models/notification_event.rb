# frozen_string_literal: true

class NotificationEvent < ApplicationRecord
  self.table_name = "notification_events"

  RECIPIENT_TYPES = %w[email user_id].freeze
  STATUSES = %w[pending sent failed rejected].freeze

  validates :notification_type, presence: true
  validates :recipient_canonical, presence: true
  validates :recipient_type, inclusion: { in: RECIPIENT_TYPES }
  validates :idempotency_hash, presence: true
  validates :idempotency_window_ts, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }
  scope :for_dispatch, -> { pending.order(:created_at).lock("FOR UPDATE SKIP LOCKED") }
end
