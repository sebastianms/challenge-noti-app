# frozen_string_literal: true

class CreateNotificationBlacklist < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_blacklist do |t|
      t.string  :recipient_canonical, limit: 320, null: false
      t.string  :scope,               limit: 16,  null: false
      t.string  :target,              limit: 64
      t.string  :source,              limit: 32,  null: false
      t.text    :reason
    end

    reversible do |dir|
      dir.up do
        execute <<~SQL
          ALTER TABLE notification_blacklist
            ADD COLUMN created_at TIMESTAMPTZ NOT NULL DEFAULT CLOCK_TIMESTAMP()
        SQL

        execute <<~SQL
          ALTER TABLE notification_blacklist
            ADD CONSTRAINT blacklist_scope_target_chk CHECK (
              (scope = 'global' AND target IS NULL)
              OR (scope IN ('type', 'channel') AND target IS NOT NULL)
            )
        SQL

        execute <<~SQL
          ALTER TABLE notification_blacklist
            ADD CONSTRAINT blacklist_scope_values_chk CHECK (
              scope IN ('global', 'type', 'channel')
            )
        SQL

        execute <<~SQL
          ALTER TABLE notification_blacklist
            ADD CONSTRAINT blacklist_source_values_chk CHECK (
              source IN ('manual', 'admin_ui', 'hard_bounce', 'dropped', 'spamreport')
            )
        SQL

        execute <<~SQL
          CREATE UNIQUE INDEX idx_blacklist_unique
            ON notification_blacklist (recipient_canonical, scope, target)
            NULLS NOT DISTINCT
        SQL

        execute <<~SQL
          CREATE INDEX idx_blacklist_lookup
            ON notification_blacklist (recipient_canonical, scope)
        SQL

        execute <<~SQL
          CREATE INDEX idx_blacklist_source_created
            ON notification_blacklist (source, created_at DESC)
        SQL
      end
    end
  end
end
