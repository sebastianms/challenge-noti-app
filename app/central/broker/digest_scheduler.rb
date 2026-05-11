# frozen_string_literal: true

class DigestScheduler
  CLAIM_SQL = <<~SQL.squish
    UPDATE pending_digests
    SET status = 'consolidating', locked_at = CLOCK_TIMESTAMP()
    WHERE id IN (
      SELECT id FROM pending_digests
      WHERE status = 'pending' AND dispatch_at <= CLOCK_TIMESTAMP()
      ORDER BY dispatch_at ASC
      LIMIT $1
      FOR UPDATE SKIP LOCKED
    )
    RETURNING id, notification_type, recipient_canonical, correlation_id, event_id, payload, rule_snapshot
  SQL

  def self.process_batch(batch_size: 50)
    claimed = ActiveRecord::Base.connection.exec_query(CLAIM_SQL, "DigestScheduler.claim", [ batch_size ]).to_a
    return 0 if claimed.empty?

    groups = claimed.group_by { |row| [ row["notification_type"], row["recipient_canonical"] ] }
    groups.each_value { |rows| consolidate_group(rows) }
    groups.size
  end

  # :nocov:
  def self.start(batch_size: 50, sleep_interval: 60)
    loop do
      count = process_batch(batch_size: batch_size)
      sleep(sleep_interval) if count.zero?
    end
  end
  # :nocov:

  private_class_method def self.consolidate_group(rows)
    digest_correlation_id = SecureRandom.uuid
    notification_type     = rows.first["notification_type"]
    recipient_canonical   = rows.first["recipient_canonical"]
    event_id              = rows.first["event_id"].to_i
    item_correlation_ids  = rows.map { |r| r["correlation_id"] }
    fused_payload         = { "digest_items" => rows.map { |r| JSON.parse(r["payload"]) } }

    rule_snapshot = JSON.parse(rows.first["rule_snapshot"])

    ActiveRecord::Base.transaction do
      DispatchQueue.create!(event_id: event_id, priority: "standard", next_attempt_at: Time.current)
      NotificationAudit.create!(
        correlation_id:      digest_correlation_id,
        event_id:            event_id,
        status:              "enqueued",
        channel:             "email",
        source:              "internal",
        notification_type:   notification_type,
        recipient_canonical: recipient_canonical,
        payload:             fused_payload,
        metadata:            { digest: true, items_count: rows.size, source_correlation_ids: item_correlation_ids, rule_id: rule_snapshot["rule_id"] }
      )
      rows.each do |row|
        NotificationAudit.create!(
          correlation_id:      row["correlation_id"],
          event_id:            row["event_id"].to_i,
          status:              "digested",
          channel:             "email",
          source:              "internal",
          notification_type:   notification_type,
          recipient_canonical: recipient_canonical,
          metadata:            { digest_correlation_id: digest_correlation_id, rule_id: rule_snapshot["rule_id"] }
        )
      end
      PendingDigest.where(id: rows.map { |r| r["id"] }).update_all(
        status:            "consolidated",
        consolidated_into: digest_correlation_id
      )
    end
  end
end
