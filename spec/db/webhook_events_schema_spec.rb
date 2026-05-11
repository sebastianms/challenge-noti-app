# frozen_string_literal: true

require "rails_helper"

RSpec.describe "webhook_events schema" do
  let(:connection) { ActiveRecord::Base.connection }

  describe "columns" do
    subject(:columns) { connection.columns("webhook_events").index_by(&:name) }

    it "has payload as jsonb not null" do
      col = columns["payload"]
      expect(col.sql_type).to eq("jsonb")
      expect(col.null).to be false
    end

    it "has status not null with default pending" do
      col = columns["status"]
      expect(col.null).to be false
      expect(col.default).to eq("pending")
    end

    it "has source not null with default sendgrid" do
      col = columns["source"]
      expect(col.null).to be false
      expect(col.default).to eq("sendgrid")
    end

    it "has attempts not null with default 0" do
      col = columns["attempts"]
      expect(col.null).to be false
      expect(col.default.to_i).to eq(0)
    end

    it "has nullable locked_at and processed_at" do
      expect(columns["locked_at"].null).to be true
      expect(columns["processed_at"].null).to be true
    end

    it "enforces status CHECK constraint" do
      expect do
        connection.execute("INSERT INTO webhook_events (payload, signature, signature_ts, status) VALUES ('[]'::jsonb, 'sig', 'ts', 'invalid_status')")
      end.to raise_error(ActiveRecord::StatementInvalid, /check/i)
    end
  end

  describe "indexes" do
    it "has partial index on (status, received_at) for pending/processing" do
      result = connection.execute(<<~SQL)
        SELECT indexname, indexdef FROM pg_indexes
        WHERE tablename = 'webhook_events'
          AND indexdef ILIKE '%pending%'
      SQL
      expect(result.count).to be >= 1
    end
  end
end
