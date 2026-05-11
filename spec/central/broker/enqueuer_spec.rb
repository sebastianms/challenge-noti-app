# frozen_string_literal: true

require "rails_helper"

RSpec.describe Enqueuer do
  let(:event_id)       { 42 }
  let(:correlation_id) { SecureRandom.uuid }

  describe ".enqueue" do
    it "creates a pending DispatchQueue job" do
      Enqueuer.enqueue(event_id: event_id, correlation_id: correlation_id)
      job = DispatchQueue.last
      expect(job.status).to eq("pending")
      expect(job.event_id).to eq(event_id)
    end

    it "creates a NotificationAudit with status enqueued" do
      Enqueuer.enqueue(event_id: event_id, correlation_id: correlation_id)
      audit = NotificationAudit.last
      expect(audit.status).to eq("enqueued")
    end

    it "stores the correlation_id on the audit record" do
      Enqueuer.enqueue(event_id: event_id, correlation_id: correlation_id)
      expect(NotificationAudit.last.correlation_id).to eq(correlation_id)
    end

    it "defaults priority to standard" do
      Enqueuer.enqueue(event_id: event_id, correlation_id: correlation_id)
      expect(DispatchQueue.last.priority).to eq("standard")
    end

    it "accepts a configurable priority" do
      Enqueuer.enqueue(event_id: event_id, correlation_id: correlation_id, priority: :critical)
      expect(DispatchQueue.last.priority).to eq("critical")
    end

    it "stamps source=internal on the audit row" do
      Enqueuer.enqueue(event_id: event_id, correlation_id: correlation_id)
      expect(NotificationAudit.last.source).to eq("internal")
    end

    it "persists recipient_canonical when provided" do
      Enqueuer.enqueue(event_id: event_id, correlation_id: correlation_id, recipient_canonical: "alice@example.com")
      expect(NotificationAudit.last.recipient_canonical).to eq("alice@example.com")
    end

    it "leaves recipient_canonical nil when omitted" do
      Enqueuer.enqueue(event_id: event_id, correlation_id: correlation_id)
      expect(NotificationAudit.last.recipient_canonical).to be_nil
    end
  end
end
