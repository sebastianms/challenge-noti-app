# frozen_string_literal: true

class WebhookEvent < ApplicationRecord
  validates :payload,      presence: true
  validates :signature,    presence: true
  validates :signature_ts, presence: true
  validates :status, inclusion: { in: %w[pending processing processed failed] }
end
