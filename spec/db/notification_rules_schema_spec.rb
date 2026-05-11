# frozen_string_literal: true

require "rails_helper"

RSpec.describe "notification_rules schema" do
  let(:connection) { ActiveRecord::Base.connection }

  describe "columns" do
    subject(:columns) { connection.columns("notification_rules").index_by(&:name) }

    it "has notification_type as text not null" do
      expect(columns["notification_type"].sql_type).to eq("text")
      expect(columns["notification_type"].null).to be false
    end

    it "has channels as text array (nullable)" do
      expect(columns["channels"].array).to be true
      expect(columns["channels"].null).to be true
    end

    it "has enabled boolean default true" do
      expect(columns["enabled"].sql_type).to eq("boolean")
      expect(columns["enabled"].default).to eq(true).or eq("true")
    end
  end

  describe "constraints" do
    it "enforces UNIQUE on notification_type" do
      NotificationRule.create!(notification_type: "x")
      expect { NotificationRule.create!(notification_type: "x") }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "rejects invalid priority value" do
      expect {
        connection.execute("INSERT INTO notification_rules (notification_type, priority, created_at, updated_at) VALUES ('y', 'invalid', NOW(), NOW())")
      }.to raise_error(ActiveRecord::StatementInvalid, /check/i)
    end

    it "rejects max_per_day = 0" do
      expect {
        connection.execute("INSERT INTO notification_rules (notification_type, max_per_day, created_at, updated_at) VALUES ('z', 0, NOW(), NOW())")
      }.to raise_error(ActiveRecord::StatementInvalid, /check/i)
    end
  end

  describe "indexes" do
    it "has partial index on notification_type WHERE enabled = TRUE" do
      result = connection.execute(<<~SQL)
        SELECT indexdef FROM pg_indexes
        WHERE tablename = 'notification_rules' AND indexname = 'notification_rules_enabled_idx'
      SQL
      expect(result.first["indexdef"]).to include("WHERE")
    end
  end
end
