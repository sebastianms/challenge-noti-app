# frozen_string_literal: true

class CreatePendingDigests < ActiveRecord::Migration[8.0]
  def change
    create_table :pending_digests do |t|
      t.text        :notification_type,   null: false
      t.text        :recipient_canonical, null: false
      t.uuid        :correlation_id,      null: false
      t.bigint      :event_id,            null: false
      t.jsonb       :payload,             null: false
      t.jsonb       :rule_snapshot,       null: false
      t.timestamptz :dispatch_at,         null: false
      t.text        :status,              null: false, default: "pending"
      t.uuid        :consolidated_into
      t.timestamptz :locked_at
      t.timestamptz :created_at,          null: false, default: -> { "NOW()" }
    end

    reversible do |dir|
      dir.up do
        execute <<~SQL
          ALTER TABLE pending_digests
            ADD CONSTRAINT pending_digests_status_check
            CHECK (status IN ('pending', 'consolidating', 'consolidated', 'orphaned'))
        SQL
        execute <<~SQL
          CREATE INDEX pending_digests_dispatch_at_idx
            ON pending_digests (dispatch_at)
            WHERE status = 'pending'
        SQL
        execute <<~SQL
          CREATE INDEX pending_digests_group_idx
            ON pending_digests (notification_type, recipient_canonical, status)
        SQL
      end
      dir.down do
        execute "DROP INDEX IF EXISTS pending_digests_dispatch_at_idx"
        execute "DROP INDEX IF EXISTS pending_digests_group_idx"
      end
    end
  end
end
