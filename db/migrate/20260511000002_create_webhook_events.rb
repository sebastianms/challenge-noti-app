# frozen_string_literal: true

class CreateWebhookEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :webhook_events do |t|
      t.text :source, null: false, default: "sendgrid"
      t.jsonb :payload, null: false
      t.text :signature, null: false
      t.text :signature_ts, null: false
      t.text :status, null: false, default: "pending"
      t.timestamptz :received_at, null: false, default: -> { "NOW()" }
      t.timestamptz :locked_at
      t.timestamptz :processed_at
      t.text :failed_reason
      t.integer :attempts, null: false, default: 0
    end

    reversible do |dir|
      dir.up do
        execute <<~SQL
          ALTER TABLE webhook_events
            ADD CONSTRAINT webhook_events_status_check
            CHECK (status IN ('pending', 'processing', 'processed', 'failed'))
        SQL

        execute <<~SQL
          CREATE INDEX webhook_events_pending_processing_idx
            ON webhook_events (status, received_at)
            WHERE status IN ('pending', 'processing')
        SQL
      end

      dir.down do
        execute "DROP INDEX IF EXISTS webhook_events_pending_processing_idx"
        execute "ALTER TABLE webhook_events DROP CONSTRAINT IF EXISTS webhook_events_status_check"
      end
    end
  end
end
