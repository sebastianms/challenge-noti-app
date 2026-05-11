# frozen_string_literal: true

class Worker
  # CLOCK_TIMESTAMP() returns wall-clock time rather than the transaction start time (NOW()).
  # This matters inside long-running transactions (e.g., DatabaseCleaner in tests) where
  # next_attempt_at set via Ruby's Time.current would otherwise be newer than NOW().
  CLAIM_SQL = <<~SQL.squish
    UPDATE dispatch_queue
    SET status = 'in_flight', locked_at = CLOCK_TIMESTAMP(), updated_at = CLOCK_TIMESTAMP()
    WHERE id IN (
      SELECT id FROM dispatch_queue
      WHERE status = 'pending' AND next_attempt_at <= CLOCK_TIMESTAMP()
      ORDER BY next_attempt_at ASC
      LIMIT $1
      FOR UPDATE SKIP LOCKED
    )
    RETURNING id, event_id, attempts
  SQL

  def self.process_batch(batch_size: 10)
    jobs = ActiveRecord::Base.connection.exec_query(CLAIM_SQL, "Worker.claim", [ batch_size ])
    jobs.each { |row| process_job(row) }
    jobs.count
  end

  # :nocov:
  def self.start(batch_size: 10, sleep_interval: 5)
    loop do
      count = process_batch(batch_size: batch_size)
      sleep(sleep_interval) if count.zero?
    end
  end
  # :nocov:

  private_class_method def self.process_job(row)
    job_id = row["id"].to_i
    event  = NotificationEvent.find_by(id: row["event_id"].to_i)

    unless event
      mark_failed(job_id, "orphan_event: event_id=#{row["event_id"]}")
      return
    end

    create_audit(event, "dispatched", "email")
    ChannelRegistry.for(:email).deliver(event, event.recipient_canonical, correlation_id: event.correlation_id)
    mark_done(job_id)
    create_audit(event, "delivered", "email")
  rescue TransientError => e
    backoff_job(job_id, e.message)
  rescue PermanentError => e
    mark_failed(job_id, e.message)
    create_audit(event, "failed", "email") if event
  end

  private_class_method def self.mark_done(job_id)
    DispatchQueue.where(id: job_id).update_all(status: "done", locked_at: nil, updated_at: Time.current)
  end

  private_class_method def self.backoff_job(job_id, reason)
    job = DispatchQueue.find(job_id)
    job.update!(
      status:         "pending",
      attempts:       job.attempts + 1,
      next_attempt_at: Time.current + job.next_backoff,
      locked_at:      nil,
      failed_reason:  reason
    )
  end

  private_class_method def self.mark_failed(job_id, reason)
    DispatchQueue.where(id: job_id).update_all(
      status:        "failed",
      failed_reason: reason,
      locked_at:     nil,
      updated_at:    Time.current
    )
  end

  private_class_method def self.create_audit(event, status, channel)
    NotificationAudit.create!(
      correlation_id: event.correlation_id,
      event_id:       event.attributes["id"],
      status:         status,
      channel:        channel
    )
  end
end
