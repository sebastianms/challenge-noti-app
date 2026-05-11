# frozen_string_literal: true

class RuleChange < ApplicationRecord
  ACTIONS = %w[created updated deleted].freeze

  belongs_to :notification_rule, optional: true
  belongs_to :admin_user

  validates :action, inclusion: { in: ACTIONS }
  validate  :before_after_coherence

  private

  def before_after_coherence
    case action
    when "created" then errors.add(:before, "must be nil for created") if self.before.present?
    when "deleted" then errors.add(:after,  "must be nil for deleted")  if self.after.present?
    when "updated"
      errors.add(:before, "must be present for updated") if self.before.blank?
      errors.add(:after,  "must be present for updated")  if self.after.blank?
    end
  end
end
