# frozen_string_literal: true

class CreateDispatchQueue < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE dispatch_queue (
        id              BIGSERIAL PRIMARY KEY,
        event_id        BIGINT NOT NULL,
        priority        TEXT NOT NULL DEFAULT 'standard'
                          CHECK (priority IN ('critical', 'standard', 'bulk')),
        status          TEXT NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending', 'in_flight', 'done', 'failed')),
        attempts        INT NOT NULL DEFAULT 0,
        next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        locked_at       TIMESTAMPTZ,
        failed_reason   TEXT,
        created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );

      CREATE INDEX idx_dispatch_queue_workable
        ON dispatch_queue (next_attempt_at, priority)
        WHERE status = 'pending';
    SQL
  end

  def down
    execute "DROP TABLE IF EXISTS dispatch_queue CASCADE"
  end
end
