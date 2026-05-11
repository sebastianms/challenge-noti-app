# frozen_string_literal: true

class WebhookEventWorker
  CLAIM_SQL = <<~SQL.squish
    UPDATE webhook_events
    SET status = 'processing', locked_at = CLOCK_TIMESTAMP(), attempts = attempts + 1
    WHERE id IN (
      SELECT id FROM webhook_events
      WHERE status = 'pending'
      ORDER BY received_at ASC
      LIMIT $1
      FOR UPDATE SKIP LOCKED
    )
    RETURNING id
  SQL

  def self.process_batch(batch_size: 10)
    claimed = ActiveRecord::Base.connection.exec_query(CLAIM_SQL, "WebhookEventWorker.claim", [ batch_size ])
    claimed.each { |row| process_event(row["id"].to_i) }
    claimed.count
  end

  # :nocov:
  def self.start(batch_size: 10, sleep_interval: 5)
    loop do
      count = process_batch(batch_size: batch_size)
      sleep(sleep_interval) if count.zero?
    end
  end
  # :nocov:

  private_class_method def self.process_event(id)
    event = WebhookEvent.find(id)
    SendgridEventProcessor.process(event)
    event.update!(status: "processed", processed_at: Time.current)
  rescue StandardError => e
    WebhookEvent.where(id: id).update_all(status: "failed", failed_reason: "#{e.class}: #{e.message}", locked_at: nil)
  end
end
