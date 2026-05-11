# frozen_string_literal: true

class NotificationBlacklist < ApplicationRecord
  self.table_name = "notification_blacklist"

  SCOPES  = %w[global type channel].freeze
  SOURCES = %w[manual admin_ui hard_bounce dropped spamreport].freeze

  validates :recipient_canonical, presence: true, length: { maximum: 320 }
  validates :scope,  inclusion: { in: SCOPES }
  validates :source, inclusion: { in: SOURCES }
  validates :target, length: { maximum: 64 }, allow_nil: true

  validate :scope_target_coherence

  scope :for_recipient, ->(canonical) { where(recipient_canonical: canonical) }

  private

  def scope_target_coherence
    case scope
    when "global"
      errors.add(:target, "must be NULL when scope=global") if target.present?
    when "type", "channel"
      errors.add(:target, "must be present when scope=#{scope}") if target.blank?
    end
  end
end
