class CreateNotificationRolloutFlags < ActiveRecord::Migration[8.1]
  def change
    create_table :notification_rollout_flags do |t|
      t.string  :notification_type, null: false
      t.string  :team_name,         null: false
      t.boolean :enrolled,          null: false, default: true
      t.text    :notes

      t.timestamps
    end

    add_index :notification_rollout_flags, :notification_type, unique: true
    add_index :notification_rollout_flags, :enrolled
  end
end
