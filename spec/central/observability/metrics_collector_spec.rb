# frozen_string_literal: true

require "rails_helper"

RSpec.describe Observability::MetricsCollector do
  subject(:collector) { described_class.new }

  describe "#queue_depth" do
    it "counts pending and in_flight jobs" do
      create(:dispatch_queue, status: "pending")
      create(:dispatch_queue, :in_flight)
      create(:dispatch_queue, :done)
      create(:dispatch_queue, :failed)

      expect(collector.queue_depth).to eq(2)
    end

    it "returns 0 when queue is empty" do
      expect(collector.queue_depth).to eq(0)
    end
  end

  describe "#dlq_size" do
    it "counts only failed jobs" do
      create(:dispatch_queue, :failed)
      create(:dispatch_queue, :failed)
      create(:dispatch_queue, status: "pending")

      expect(collector.dlq_size).to eq(2)
    end

    it "returns 0 when no failures" do
      expect(collector.dlq_size).to eq(0)
    end
  end

  describe "#events_ingested_24h" do
    it "counts events created in the last 24 hours" do
      create(:notification_event, created_at: 23.hours.ago)
      create(:notification_event, created_at: 25.hours.ago)

      expect(collector.events_ingested_24h).to eq(1)
    end

    it "returns 0 when no recent events" do
      create(:notification_event, created_at: 2.days.ago)

      expect(collector.events_ingested_24h).to eq(0)
    end
  end

  describe "#dispatch_errors_by_class" do
    it "groups failed jobs by error class" do
      create(:dispatch_queue, :failed, failed_reason: "TransientError: timeout")
      create(:dispatch_queue, :failed, failed_reason: "TransientError: timeout")
      create(:dispatch_queue, :failed, failed_reason: "PermanentError: invalid")

      result = collector.dispatch_errors_by_class

      expect(result["TransientError"]).to eq(2)
      expect(result["PermanentError"]).to eq(1)
    end

    it "groups blank reason as Unknown" do
      create(:dispatch_queue, :failed, failed_reason: nil)

      expect(collector.dispatch_errors_by_class["Unknown"]).to eq(1)
    end

    it "returns empty hash when no failed jobs" do
      expect(collector.dispatch_errors_by_class).to eq({})
    end
  end

  describe "#bounce_rate_5m" do
    it "returns ratio of bounces to total sendgrid webhook audits in last 5 min" do
      create(:notification_audit, :from_webhook, status: "bounced", created_at: 2.minutes.ago)
      create(:notification_audit, :from_webhook, status: "delivered", created_at: 2.minutes.ago)
      create(:notification_audit, :from_webhook, status: "bounced", created_at: 6.minutes.ago)

      expect(collector.bounce_rate_5m).to eq(0.5)
    end

    it "returns 0.0 when no webhook audits in window" do
      expect(collector.bounce_rate_5m).to eq(0.0)
    end

    it "returns 0.0 when no bounces in window" do
      create(:notification_audit, :from_webhook, status: "delivered", created_at: 1.minute.ago)

      expect(collector.bounce_rate_5m).to eq(0.0)
    end
  end

  describe "#webhook_lag_seconds" do
    it "returns age of oldest pending webhook event" do
      create(:webhook_event, status: "pending", received_at: 10.seconds.ago)
      create(:webhook_event, status: "pending", received_at: 5.seconds.ago)
      create(:webhook_event, :processed)

      expect(collector.webhook_lag_seconds).to be >= 10.0
    end

    it "includes processing events" do
      create(:webhook_event, :processing, received_at: 20.seconds.ago)

      expect(collector.webhook_lag_seconds).to be >= 20.0
    end

    it "returns 0.0 when no pending or processing events" do
      create(:webhook_event, :processed)

      expect(collector.webhook_lag_seconds).to eq(0.0)
    end
  end

  describe "#collect" do
    it "returns a hash with all metric keys" do
      result = collector.collect

      expect(result.keys).to contain_exactly(
        :queue_depth, :dlq_size, :events_ingested_24h,
        :dispatch_errors_by_class, :bounce_rate_5m, :webhook_lag_seconds
      )
    end
  end
end
