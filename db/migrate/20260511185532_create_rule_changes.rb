# frozen_string_literal: true

class CreateRuleChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :rule_changes do |t|
      t.references :notification_rule, null: true,  foreign_key: { on_delete: :nullify }
      t.references :admin_user,        null: false, foreign_key: { on_delete: :restrict }
      t.string  :action, null: false
      t.jsonb   :before
      t.jsonb   :after
      t.datetime :changed_at, null: false, default: -> { "clock_timestamp()" }
    end

    add_check_constraint :rule_changes,
      "action IN ('created', 'updated', 'deleted')",
      name: "rule_changes_action_chk"

    add_index :rule_changes, [ :notification_rule_id, :changed_at ], order: { changed_at: :desc }, name: "idx_rule_changes_rule_time"
    add_index :rule_changes, [ :admin_user_id, :changed_at ],        order: { changed_at: :desc }, name: "idx_rule_changes_user_time"
    add_index :rule_changes, :changed_at,                            order: :desc,                 name: "idx_rule_changes_time"
  end
end
