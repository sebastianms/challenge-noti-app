# frozen_string_literal: true

class ExtendNotificationAuditWithSourceAndRecipient < ActiveRecord::Migration[8.0]
  def change
    add_column :notification_audit, :recipient_canonical, :text
    add_column :notification_audit, :source, :text, null: false, default: "internal"

    reversible do |dir|
      dir.up do
        execute <<~SQL
          ALTER TABLE notification_audit
            ADD CONSTRAINT notification_audit_source_check
            CHECK (source IN ('internal', 'sendgrid_webhook'))
        SQL

        execute <<~SQL
          CREATE INDEX notification_audit_recipient_canonical_idx
            ON notification_audit (recipient_canonical)
            WHERE recipient_canonical IS NOT NULL
        SQL

        execute <<~SQL
          CREATE INDEX notification_audit_status_created_at_idx
            ON notification_audit (status, created_at)
        SQL
      end

      dir.down do
        execute "DROP INDEX IF EXISTS notification_audit_recipient_canonical_idx"
        execute "DROP INDEX IF EXISTS notification_audit_status_created_at_idx"
        execute "ALTER TABLE notification_audit DROP CONSTRAINT IF EXISTS notification_audit_source_check"
      end
    end
  end
end
