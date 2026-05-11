# frozen_string_literal: true

require "ostruct"

class EventBuilder
  def self.build(notification_class:, recipient:, context: {}, priority: :standard)
    new(notification_class:, recipient:, context:, priority:).call
  end

  def initialize(notification_class:, recipient:, context:, priority: :standard)
    @notification_class = notification_class
    @recipient_input    = recipient
    @context            = context || {}
    @priority           = priority
  end

  def call
    normalized = RecipientNormalizer.normalize(@recipient_input)

    type_id    = @notification_class.resolved_notification_type
    window     = @notification_class.resolved_idempotency_window
    window_ts  = floor_to_window(Time.current.utc, window)
    context_id = extract_context_id(@context)

    hash = IdempotencyHash.compute(
      notification_type:    type_id,
      recipient_canonical:  normalized[:canonical],
      context_id:           context_id,
      window_ts:            window_ts
    )

    persist(
      notification_type:    type_id,
      recipient_canonical:  normalized[:canonical],
      recipient_type:       normalized[:type].to_s,
      context_id:           context_id,
      payload:              serialize_payload(@context),
      idempotency_hash:     hash,
      idempotency_window_ts: window_ts
    )
  rescue ArgumentError => e
    SendResult.rejected(reason: e.message)
  end

  private

  def floor_to_window(time, window)
    seconds = window.to_i
    Time.at((time.to_i / seconds) * seconds).utc
  end

  def extract_context_id(context)
    return "no_context" if context.empty?

    candidate = context[:id] || context.values.find { |v| String === v || Integer === v }
    candidate.nil? ? "no_context" : candidate.to_s
  end

  def serialize_payload(context)
    JSON.generate(context)
    context.deep_stringify_keys
  rescue JSON::GeneratorError, Encoding::UndefinedConversionError, NoMethodError => e
    raise ArgumentError, "context not JSON-serializable: #{e.message}"
  end

  def persist(attrs)
    insert_sql = <<~SQL.squish
      INSERT INTO notification_events
        (notification_type, recipient_canonical, recipient_type, context_id,
         payload, idempotency_hash, idempotency_window_ts)
      VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7)
      ON CONFLICT (idempotency_hash, idempotency_window_ts) DO NOTHING
      RETURNING correlation_id, id;
    SQL

    params = [
      attrs[:notification_type],
      attrs[:recipient_canonical],
      attrs[:recipient_type],
      attrs[:context_id],
      JSON.generate(attrs[:payload]),
      attrs[:idempotency_hash],
      attrs[:idempotency_window_ts]
    ]

    send_result = ActiveRecord::Base.transaction do
      conn   = ActiveRecord::Base.connection
      result = conn.exec_query(insert_sql, "EventBuilder.persist", params)

      if result.rows.any?
        correlation_id, event_id = result.rows.first
        blacklist_entry = BlacklistEvaluator.match(
          event: OpenStruct.new(
            recipient_canonical: attrs[:recipient_canonical],
            notification_type:   attrs[:notification_type]
          ),
          channel: "email"
        )

        if blacklist_entry
          audit_blacklisted(
            correlation_id:      correlation_id,
            event_id:            event_id.to_i,
            notification_type:   attrs[:notification_type],
            recipient_canonical: attrs[:recipient_canonical],
            entry:               blacklist_entry
          )
          SendResult.filtered(correlation_id: correlation_id)
        else
          apply_decision(
            correlation_id:      correlation_id,
            event_id:            event_id.to_i,
            notification_type:   attrs[:notification_type],
            recipient_canonical: attrs[:recipient_canonical],
            payload:             attrs[:payload]
          )
          SendResult.created(correlation_id: correlation_id)
        end
      else
        existing_id = conn.exec_query(
          "SELECT correlation_id FROM notification_events WHERE idempotency_hash = $1 ORDER BY created_at DESC LIMIT 1",
          "EventBuilder.find_duplicate",
          [ attrs[:idempotency_hash] ]
        ).rows.first&.first
        SendResult.duplicate(correlation_id: existing_id)
      end
    end

    log_result(send_result, attrs)
    send_result
  end

  def apply_decision(correlation_id:, event_id:, notification_type:, recipient_canonical:, payload:)
    event = OpenStruct.new(
      correlation_id:      correlation_id,
      notification_type:   notification_type,
      recipient_canonical: recipient_canonical
    )
    decision = RulesEngine.decide(event: event)

    case decision.kind
    when :dispatch
      Enqueuer.enqueue(
        event_id:            event_id,
        correlation_id:      correlation_id,
        notification_type:   notification_type,
        recipient_canonical: recipient_canonical,
        priority:            decision.priority || @priority
      )
    when :digest
      enqueue_digest(
        correlation_id:      correlation_id,
        event_id:            event_id,
        notification_type:   notification_type,
        recipient_canonical: recipient_canonical,
        payload:             payload,
        decision:            decision
      )
    when :filter
      NotificationAudit.create!(
        correlation_id:      correlation_id,
        event_id:            event_id,
        status:              "filtered",
        channel:             "email",
        source:              "internal",
        notification_type:   notification_type,
        recipient_canonical: recipient_canonical,
        metadata:            { reason: decision.reason, rule_id: decision.rule_id }
      )
    end
  end

  def audit_blacklisted(correlation_id:, event_id:, notification_type:, recipient_canonical:, entry:)
    NotificationAudit.create!(
      correlation_id:      correlation_id,
      event_id:            event_id,
      status:              "filtered",
      channel:             "email",
      source:              "internal",
      notification_type:   notification_type,
      recipient_canonical: recipient_canonical,
      metadata:            { reason: "blacklisted", blacklist_id: entry.id, scope: entry.scope, target: entry.target }
    )
  end

  def enqueue_digest(correlation_id:, event_id:, notification_type:, recipient_canonical:, payload:, decision:)
    dispatch_at = Time.current + decision.digest_window_seconds.seconds
    PendingDigest.create!(
      correlation_id:      correlation_id,
      event_id:            event_id,
      notification_type:   notification_type,
      recipient_canonical: recipient_canonical,
      payload:             payload,
      rule_snapshot:       { rule_id: decision.rule_id, digest_window_seconds: decision.digest_window_seconds },
      dispatch_at:         dispatch_at,
      status:              "pending"
    )
    NotificationAudit.create!(
      correlation_id:      correlation_id,
      event_id:            event_id,
      status:              "pending_digest",
      channel:             "email",
      source:              "internal",
      notification_type:   notification_type,
      recipient_canonical: recipient_canonical,
      metadata:            { rule_id: decision.rule_id, dispatch_at: dispatch_at.iso8601 }
    )
  end

  def log_result(result, attrs)
    Rails.logger.info({
      event:             "notification_ingested",
      state:             result.state,
      correlation_id:    result.correlation_id,
      notification_type: attrs[:notification_type],
      recipient_type:    attrs[:recipient_type]
    }.to_json)
  end
end
