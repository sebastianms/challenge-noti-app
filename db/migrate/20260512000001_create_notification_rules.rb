# frozen_string_literal: true

class CreateNotificationRules < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_rules do |t|
      t.text    :notification_type, null: false
      t.text    :channels, array: true
      t.integer :max_per_day
      t.integer :cooldown_seconds
      t.integer :digest_window_seconds
      t.text    :priority
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end

    reversible do |dir|
      dir.up do
        execute <<~SQL
          ALTER TABLE notification_rules
            ADD CONSTRAINT notification_rules_type_unique UNIQUE (notification_type)
        SQL
        execute <<~SQL
          ALTER TABLE notification_rules
            ADD CONSTRAINT notification_rules_priority_check
            CHECK (priority IS NULL OR priority IN ('critical', 'standard', 'bulk'))
        SQL
        execute <<~SQL
          ALTER TABLE notification_rules
            ADD CONSTRAINT notification_rules_max_per_day_positive
            CHECK (max_per_day IS NULL OR max_per_day > 0)
        SQL
        execute <<~SQL
          ALTER TABLE notification_rules
            ADD CONSTRAINT notification_rules_cooldown_positive
            CHECK (cooldown_seconds IS NULL OR cooldown_seconds > 0)
        SQL
        execute <<~SQL
          ALTER TABLE notification_rules
            ADD CONSTRAINT notification_rules_digest_positive
            CHECK (digest_window_seconds IS NULL OR digest_window_seconds > 0)
        SQL
        execute <<~SQL
          CREATE INDEX notification_rules_enabled_idx
            ON notification_rules (notification_type)
            WHERE enabled = TRUE
        SQL
      end
      dir.down do
        execute "DROP INDEX IF EXISTS notification_rules_enabled_idx"
      end
    end
  end
end
