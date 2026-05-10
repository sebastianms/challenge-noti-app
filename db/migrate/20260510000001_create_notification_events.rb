# frozen_string_literal: true

class CreateNotificationEvents < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE notification_events (
        id                       BIGSERIAL,
        notification_type        TEXT NOT NULL,
        recipient_canonical      TEXT NOT NULL,
        recipient_type           TEXT NOT NULL CHECK (recipient_type IN ('email', 'user_id')),
        context_id               TEXT,
        payload                  JSONB NOT NULL DEFAULT '{}'::jsonb,
        idempotency_hash         TEXT NOT NULL,
        idempotency_window_ts    TIMESTAMPTZ NOT NULL,
        correlation_id           UUID NOT NULL DEFAULT gen_random_uuid(),
        status                   TEXT NOT NULL DEFAULT 'pending'
                                   CHECK (status IN ('pending', 'sent', 'failed', 'rejected')),
        created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
        PRIMARY KEY (id, idempotency_window_ts),
        UNIQUE (idempotency_hash, idempotency_window_ts),
        UNIQUE (correlation_id, idempotency_window_ts)
      ) PARTITION BY RANGE (idempotency_window_ts);

      CREATE INDEX idx_notification_events_status_created_at
        ON notification_events (status, created_at);

      CREATE INDEX idx_notification_events_notification_type
        ON notification_events (notification_type);

      CREATE INDEX idx_notification_events_recipient
        ON notification_events (recipient_canonical);

      CREATE INDEX idx_notification_events_correlation_id
        ON notification_events (correlation_id);
    SQL

    # Default partition covers all dates; named partitions added in production ops
    execute <<~SQL
      CREATE TABLE notification_events_default
        PARTITION OF notification_events DEFAULT;
    SQL
  end

  def down
    execute "DROP TABLE IF EXISTS notification_events CASCADE"
  end
end
