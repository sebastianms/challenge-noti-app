# frozen_string_literal: true

class SendgridEventProcessor
  EVENT_TO_STATUS = {
    "delivered"  => "delivered",
    "bounce"     => "bounced",
    "dropped"    => "dropped",
    "deferred"   => "deferred",
    "spamreport" => "spam_reported"
  }.freeze

  HARD_BOUNCE_SOURCES = {
    "dropped"    => "dropped",
    "spamreport" => "spamreport"
  }.freeze

  def self.process(webhook_event)
    events = Array(webhook_event.payload)
    events.each { |evt| process_one(evt) }
  end

  private_class_method def self.process_one(evt)
    ActiveRecord::Base.transaction do
      create_audit(evt)
      blacklist_if_hard_failure(evt)
    end
  end

  private_class_method def self.create_audit(evt)
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

  private_class_method def self.blacklist_if_hard_failure(evt)
    source = hard_failure_source(evt)
    return unless source

    canonical = canonicalize(evt["email"])
    return if canonical.blank?

    NotificationBlacklist.insert_all(
      [ {
        recipient_canonical: canonical,
        scope:               "channel",
        target:              "email",
        source:              source,
        reason:              "#{evt['reason']} (sg_event_id=#{evt['sg_event_id']})"
      } ],
      returning: false,
      unique_by: :idx_blacklist_unique
    )
  end

  private_class_method def self.hard_failure_source(evt)
    return HARD_BOUNCE_SOURCES[evt["event"]] if HARD_BOUNCE_SOURCES.key?(evt["event"])
    return "hard_bounce" if evt["event"] == "bounce" && evt["type"] == "bounce"

    nil
  end

  private_class_method def self.canonicalize(raw)
    RecipientNormalizer.normalize(raw)[:canonical]
  # :nocov:
  rescue ArgumentError
    nil
    # :nocov:
  end
end
