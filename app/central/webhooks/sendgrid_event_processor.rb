# frozen_string_literal: true

class SendgridEventProcessor
  EVENT_TO_STATUS = {
    "delivered"  => "delivered",
    "bounce"     => "bounced",
    "dropped"    => "dropped",
    "deferred"   => "deferred",
    "spamreport" => "spam_reported"
  }.freeze

  def self.process(webhook_event)
    events = Array(webhook_event.payload)
    events.each do |evt|
      status = EVENT_TO_STATUS[evt["event"]] || "raw"
      NotificationAudit.create!(
        correlation_id:      evt["correlation_id"].presence || SecureRandom.uuid,
        status:              status,
        channel:             "email",
        source:              "sendgrid_webhook",
        recipient_canonical: evt["email"],
        metadata:            { type: evt["event"], sg_timestamp: evt["timestamp"], sg_event_id: evt["sg_event_id"] }
      )
    end
  end
end
