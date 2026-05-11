# frozen_string_literal: true

require "rails_helper"

RSpec.describe "dispatch_queue schema" do
  let(:connection) { ActiveRecord::Base.connection }

  describe "columns" do
    subject(:columns) { connection.columns("dispatch_queue").index_by(&:name) }

    it "has id as bigserial primary key" do
      expect(columns["id"].sql_type).to match(/bigint/i)
    end

    it "has event_id bigint not null" do
      col = columns["event_id"]
      expect(col.sql_type).to match(/bigint/i)
      expect(col.null).to be false
    end

    it "has status with default pending" do
      col = columns["status"]
      expect(col.default).to eq("pending")
    end

    it "has attempts with default 0" do
      col = columns["attempts"]
      expect(col.default.to_i).to eq(0)
    end

    it "has next_attempt_at timestamptz not null" do
      col = columns["next_attempt_at"]
      expect(col.sql_type).to match(/timestamp/i)
      expect(col.null).to be false
    end

    it "has failed_reason nullable" do
      expect(columns["failed_reason"].null).to be true
    end
  end

  describe "CHECK constraints" do
    it "rejects invalid priority" do
      expect {
        ActiveRecord::Base.connection.execute(
          "INSERT INTO dispatch_queue (event_id, priority, next_attempt_at) VALUES (1, 'invalid', NOW())"
        )
      }.to raise_error(ActiveRecord::StatementInvalid, /check/i)
    end

    it "rejects invalid status" do
      expect {
        ActiveRecord::Base.connection.execute(
          "INSERT INTO dispatch_queue (event_id, status, next_attempt_at) VALUES (1, 'bad', NOW())"
        )
      }.to raise_error(ActiveRecord::StatementInvalid, /check/i)
    end
  end

  describe "partial index" do
    it "has workable index for pending rows" do
      index = connection.indexes("dispatch_queue").find { |i| i.name == "idx_dispatch_queue_workable" }
      expect(index).not_to be_nil
      expect(index.where).to match(/status.*pending/i)
    end
  end
end
