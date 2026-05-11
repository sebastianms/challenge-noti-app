# frozen_string_literal: true

class CreateNotificationAudit < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE notification_audit (
        id             BIGSERIAL,
        correlation_id UUID NOT NULL,
        event_id       BIGINT,
        status         TEXT NOT NULL,
        channel        TEXT,
        rule_snapshot  JSONB,
        payload        JSONB,
        metadata       JSONB,
        created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        PRIMARY KEY (id, created_at)
      ) PARTITION BY RANGE (created_at);

      CREATE TABLE notification_audit_2026_05
        PARTITION OF notification_audit
        FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');

      CREATE INDEX ON notification_audit (correlation_id);
      CREATE INDEX ON notification_audit USING GIN (payload);
      CREATE INDEX ON notification_audit USING GIN (metadata);
    SQL
  end

  def down
    execute "DROP TABLE IF EXISTS notification_audit CASCADE"
  end
end
