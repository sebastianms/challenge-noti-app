# frozen_string_literal: true

class AddNotificationTypeToAudit < ActiveRecord::Migration[8.0]
  def change
    add_column :notification_audit, :notification_type, :text

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE INDEX notification_audit_rate_limit_idx
            ON notification_audit (notification_type, recipient_canonical, created_at)
            WHERE notification_type IS NOT NULL AND recipient_canonical IS NOT NULL
        SQL
      end
      dir.down do
        execute "DROP INDEX IF EXISTS notification_audit_rate_limit_idx"
      end
    end
  end
end
