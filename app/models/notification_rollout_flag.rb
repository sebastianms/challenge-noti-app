# frozen_string_literal: true

class NotificationRolloutFlag < ApplicationRecord
  validates :notification_type, presence: true, uniqueness: true
  validates :team_name, presence: true
  validates :enrolled, inclusion: { in: [ true, false ] }

  scope :enrolled,    -> { where(enrolled: true) }
  scope :not_enrolled, -> { where(enrolled: false) }

  def self.enrolled?(notification_type)
    flag = find_by(notification_type: notification_type)
    flag.nil? || flag.enrolled?
  end
end
