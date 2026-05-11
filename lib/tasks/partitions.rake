# frozen_string_literal: true

namespace :partitions do
  desc "Rotate notification_audit partitions: create next month, drop expired"
  task rotate: :environment do
    retention = ENV.fetch("AUDIT_RETENTION_MONTHS", "6").to_i
    manager   = PartitionManager.new(table: "notification_audit", retention_months: retention)
    manager.rotate
    puts "[partitions:rotate] rotated notification_audit (retention=#{retention} months)"
  end
end
