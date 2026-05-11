# frozen_string_literal: true

require "rails_helper"

RSpec.describe PartitionManager do
  let(:conn) { ActiveRecord::Base.connection }

  def partition_exists?(name)
    conn.exec_query("SELECT 1 FROM pg_class WHERE relname = $1", "test", [ name ]).any?
  end

  def create_partition(name, from, to)
    conn.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS #{name}
        PARTITION OF notification_audit
        FOR VALUES FROM ('#{from}') TO ('#{to}');
    SQL
  end

  def drop_partition(name)
    conn.execute("DROP TABLE IF EXISTS #{name}")
  end

  describe "#create_next_month_partition" do
    let(:manager) { described_class.new(table: "notification_audit", retention_months: 6) }

    it "creates the partition for the next month" do
      now = Time.zone.parse("2026-05-15")
      name = manager.create_next_month_partition(now: now)
      expect(name).to eq("notification_audit_2026_06")
      expect(partition_exists?(name)).to be true
      drop_partition(name)
    end

    it "is idempotent (second call does not raise)" do
      now = Time.zone.parse("2026-05-15")
      manager.create_next_month_partition(now: now)
      expect { manager.create_next_month_partition(now: now) }.not_to raise_error
      drop_partition("notification_audit_2026_06")
    end
  end

  describe "#drop_old_partitions" do
    let(:manager) { described_class.new(table: "notification_audit", retention_months: 6) }

    around do |example|
      create_partition("notification_audit_2025_06", "2025-06-01", "2025-07-01")
      create_partition("notification_audit_2025_11", "2025-11-01", "2025-12-01")
      example.run
      drop_partition("notification_audit_2025_06")
      drop_partition("notification_audit_2025_11")
    end

    it "drops partitions older than retention_months" do
      now = Time.zone.parse("2026-05-15")
      dropped = manager.drop_old_partitions(now: now)
      expect(dropped).to include("notification_audit_2025_06")
      expect(partition_exists?("notification_audit_2025_06")).to be false
    end

    it "preserves partitions within retention window" do
      now = Time.zone.parse("2026-05-15")
      manager.drop_old_partitions(now: now)
      expect(partition_exists?("notification_audit_2025_11")).to be true
    end
  end

  describe "safety guardrail" do
    let(:manager) { described_class.new(table: "notification_audit", retention_months: 2) }

    it "skips drop when retention_months < 3 and logs a warning" do
      expect(Rails.logger).to receive(:warn).with(/below safety minimum/)
      now = Time.zone.parse("2026-05-15")
      result = manager.drop_old_partitions(now: now)
      expect(result).to eq([])
    end
  end

  describe "#rotate" do
    let(:manager) { described_class.new(table: "notification_audit", retention_months: 6) }

    it "combines create_next + drop_old" do
      create_partition("notification_audit_2024_01", "2024-01-01", "2024-02-01")
      now = Time.zone.parse("2026-05-15")
      manager.rotate(now: now)
      expect(partition_exists?("notification_audit_2026_06")).to be true
      expect(partition_exists?("notification_audit_2024_01")).to be false
      drop_partition("notification_audit_2026_06")
    end
  end
end
