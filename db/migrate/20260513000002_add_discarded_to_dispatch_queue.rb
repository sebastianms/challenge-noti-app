# frozen_string_literal: true

class AddDiscardedToDispatchQueue < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      ALTER TABLE dispatch_queue DROP CONSTRAINT IF EXISTS dispatch_queue_status_check
    SQL

    execute <<~SQL
      ALTER TABLE dispatch_queue
        ADD CONSTRAINT dispatch_queue_status_check
        CHECK (status IN ('pending', 'in_flight', 'done', 'failed', 'discarded'))
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE dispatch_queue DROP CONSTRAINT IF EXISTS dispatch_queue_status_check
    SQL

    execute <<~SQL
      ALTER TABLE dispatch_queue
        ADD CONSTRAINT dispatch_queue_status_check
        CHECK (status IN ('pending', 'in_flight', 'done', 'failed'))
    SQL
  end
end
