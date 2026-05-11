# frozen_string_literal: true

require "rails_helper"

RSpec.describe "pending_digests schema" do
  let(:connection) { ActiveRecord::Base.connection }

  describe "columns" do
    subject(:columns) { connection.columns("pending_digests").index_by(&:name) }

    it "has notification_type not null" do
      expect(columns["notification_type"].null).to be false
    end

    it "has recipient_canonical not null" do
      expect(columns["recipient_canonical"].null).to be false
    end

    it "has payload and rule_snapshot as jsonb not null" do
      expect(columns["payload"].sql_type).to eq("jsonb")
      expect(columns["payload"].null).to be false
      expect(columns["rule_snapshot"].sql_type).to eq("jsonb")
      expect(columns["rule_snapshot"].null).to be false
    end

    it "has status default pending" do
      expect(columns["status"].default).to eq("pending")
    end
  end

  describe "constraints" do
    it "enforces CHECK on status" do
      expect {
        connection.execute(<<~SQL)
          INSERT INTO pending_digests (notification_type, recipient_canonical, correlation_id, event_id, payload, rule_snapshot, dispatch_at, status)
          VALUES ('x', 'a@b.com', gen_random_uuid(), 1, '{}'::jsonb, '{}'::jsonb, NOW(), 'invalid')
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /check/i)
    end
  end

  describe "indexes" do
    it "has partial index on dispatch_at WHERE status = pending" do
      result = connection.execute(<<~SQL)
        SELECT indexdef FROM pg_indexes
        WHERE tablename = 'pending_digests' AND indexname = 'pending_digests_dispatch_at_idx'
      SQL
      expect(result.first["indexdef"]).to include("WHERE")
    end

    it "has composite index (notification_type, recipient_canonical, status)" do
      result = connection.execute(<<~SQL)
        SELECT indexdef FROM pg_indexes
        WHERE tablename = 'pending_digests' AND indexname = 'pending_digests_group_idx'
      SQL
      expect(result.count).to eq(1)
    end
  end
end
