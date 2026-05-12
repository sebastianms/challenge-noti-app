# frozen_string_literal: true

class NotificationTemplate < ApplicationRecord
  validates :notification_type, presence: true, format: { with: /\A[a-z_]+\z/ }
  validates :title, presence: true, length: { maximum: 2000 }
  validates :body,  presence: true, length: { maximum: 2000 }
  validates :digest_template, length: { maximum: 4000 }, allow_nil: true
  validates :locale, presence: true

  after_save    { Templates::TemplateCache.invalidate(notification_type, locale) }
  after_destroy { Templates::TemplateCache.invalidate(notification_type, locale) }
end
