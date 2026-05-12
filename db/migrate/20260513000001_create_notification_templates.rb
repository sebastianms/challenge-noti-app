# frozen_string_literal: true

class CreateNotificationTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_templates do |t|
      t.text :notification_type, null: false
      t.text :locale,            null: false, default: "es"
      t.text :title,             null: false
      t.text :body,              null: false
      t.text :digest_template

      t.timestamps null: false
    end

    reversible do |dir|
      dir.up do
        execute <<~SQL
          ALTER TABLE notification_templates
            ADD CONSTRAINT notification_templates_type_format_chk
            CHECK (notification_type ~ '^[a-z_]+$')
        SQL

        execute <<~SQL
          CREATE UNIQUE INDEX idx_notification_templates_type_locale
            ON notification_templates (notification_type, locale)
        SQL
      end

      dir.down do
        execute "DROP INDEX IF EXISTS idx_notification_templates_type_locale"
      end
    end
  end
end
