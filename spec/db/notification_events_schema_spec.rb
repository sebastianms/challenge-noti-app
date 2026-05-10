# frozen_string_literal: true

require "rails_helper"

RSpec.describe "notification_events schema", type: :model do
  let(:conn) { ActiveRecord::Base.connection }

  describe "columns" do
    subject(:columns) { conn.columns("notification_events").index_by(&:name) }

    it "has all required columns" do
      expect(columns.keys).to include(
        "id", "notification_type", "recipient_canonical", "recipient_type",
        "context_id", "payload", "idempotency_hash", "idempotency_window_ts",
        "correlation_id", "status", "created_at"
      )
    end

    it "requires notification_type" do
      expect(columns["notification_type"].null).to be false
    end

    it "requires recipient_canonical" do
      expect(columns["recipient_canonical"].null).to be false
    end

    it "requires idempotency_hash" do
      expect(columns["idempotency_hash"].null).to be false
    end

    it "requires idempotency_window_ts" do
      expect(columns["idempotency_window_ts"].null).to be false
    end

    it "has status defaulting to pending" do
      expect(columns["status"].default).to eq("pending")
    end

    it "has payload defaulting to empty json" do
      expect(columns["payload"].default).to eq("{}")
    end
  end

  describe "indexes" do
    subject(:index_names) { conn.indexes("notification_events").map(&:name) }

    it "has index on status and created_at" do
      expect(index_names).to include("idx_notification_events_status_created_at")
    end

    it "has index on notification_type" do
      expect(index_names).to include("idx_notification_events_notification_type")
    end

    it "has index on recipient_canonical" do
      expect(index_names).to include("idx_notification_events_recipient")
    end

    it "has index on correlation_id" do
      expect(index_names).to include("idx_notification_events_correlation_id")
    end
  end

  describe "partitioning" do
    it "registers at least one partition (default)" do
      partitions = conn.select_values(<<~SQL)
        SELECT inhrelid::regclass::text
        FROM pg_inherits
        WHERE inhparent = 'notification_events'::regclass
      SQL

      expect(partitions).to include("notification_events_default")
    end
  end
end
