# frozen_string_literal: true

require "rails_helper"

RSpec.describe "notification_audit schema" do
  let(:connection) { ActiveRecord::Base.connection }

  describe "partitioning" do
    it "is partitioned by range on created_at" do
      result = connection.execute(<<~SQL).first
        SELECT partstrat
        FROM pg_partitioned_table pt
        JOIN pg_class c ON c.oid = pt.partrelid
        WHERE c.relname = 'notification_audit'
      SQL
      expect(result["partstrat"]).to eq("r")
    end

    it "has the 2026_05 partition" do
      result = connection.execute(<<~SQL)
        SELECT inhrelid::regclass::text AS partition_name
        FROM pg_inherits
        JOIN pg_class parent ON parent.oid = inhparent
        WHERE parent.relname = 'notification_audit'
      SQL
      names = result.map { |r| r["partition_name"] }
      expect(names).to include("notification_audit_2026_05")
    end
  end

  describe "indexes" do
    subject(:indexes) { connection.indexes("notification_audit") }

    it "has an index on correlation_id" do
      expect(indexes.any? { |i| i.columns.include?("correlation_id") }).to be true
    end

    it "has a GIN index on payload" do
      result = connection.execute(<<~SQL)
        SELECT indexname FROM pg_indexes
        WHERE tablename = 'notification_audit'
          AND indexdef ILIKE '%gin%payload%'
      SQL
      expect(result.count).to be >= 1
    end

    it "has a GIN index on metadata" do
      result = connection.execute(<<~SQL)
        SELECT indexname FROM pg_indexes
        WHERE tablename = 'notification_audit'
          AND indexdef ILIKE '%gin%metadata%'
      SQL
      expect(result.count).to be >= 1
    end
  end

  describe "columns" do
    subject(:columns) { connection.columns("notification_audit").index_by(&:name) }

    it "has correlation_id as uuid not null" do
      col = columns["correlation_id"]
      expect(col.sql_type).to match(/uuid/i)
      expect(col.null).to be false
    end

    it "has status not null" do
      expect(columns["status"].null).to be false
    end

    it "has source not null with default internal" do
      col = columns["source"]
      expect(col).not_to be_nil
      expect(col.null).to be false
      expect(col.default).to eq("internal")
    end

    it "has recipient_canonical as nullable text" do
      col = columns["recipient_canonical"]
      expect(col).not_to be_nil
      expect(col.null).to be true
    end

    it "enforces source CHECK constraint" do
      expect do
        connection.execute("INSERT INTO notification_audit_2026_05 (correlation_id, status, source) VALUES (gen_random_uuid(), 'enqueued', 'invalid_source')")
      end.to raise_error(ActiveRecord::StatementInvalid, /check/i)
    end
  end

  describe "new indexes" do
    it "has partial index on recipient_canonical where not null" do
      result = connection.execute(<<~SQL)
        SELECT indexname, indexdef FROM pg_indexes
        WHERE tablename LIKE 'notification_audit%'
          AND indexdef ILIKE '%recipient_canonical%'
          AND indexdef ILIKE '%where%'
      SQL
      expect(result.count).to be >= 1
    end

    it "has composite index on (status, created_at)" do
      result = connection.execute(<<~SQL)
        SELECT indexname FROM pg_indexes
        WHERE tablename LIKE 'notification_audit%'
          AND indexdef ILIKE '%status%created_at%'
      SQL
      expect(result.count).to be >= 1
    end

    it "has rate-limit covering index on (notification_type, recipient_canonical, created_at)" do
      result = connection.execute(<<~SQL)
        SELECT indexname FROM pg_indexes
        WHERE tablename = 'notification_audit'
          AND indexname = 'notification_audit_rate_limit_idx'
      SQL
      expect(result.count).to eq(1)
    end

    it "has notification_type column nullable" do
      col = connection.columns("notification_audit").find { |c| c.name == "notification_type" }
      expect(col).not_to be_nil
      expect(col.null).to be true
    end
  end
end
