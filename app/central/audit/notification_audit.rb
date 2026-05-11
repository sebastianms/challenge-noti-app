# frozen_string_literal: true

class NotificationAudit < ApplicationRecord
  self.table_name = "notification_audit"

  validates :correlation_id, presence: true
  validates :status,         presence: true
end
