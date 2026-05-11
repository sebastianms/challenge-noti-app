# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookEventWorker, type: :model do
  describe ".process_batch" do
    it "marks a pending event as processed" do
      we = create(:webhook_event, payload: [ SendgridWebhookSigner.delivered_event ])
      WebhookEventWorker.process_batch
      expect(we.reload.status).to eq("processed")
      expect(we.processed_at).to be_present
    end

    it "creates NotificationAudit entries via SendgridEventProcessor" do
      create(:webhook_event, payload: [ SendgridWebhookSigner.delivered_event, SendgridWebhookSigner.bounce_event ])
      expect { WebhookEventWorker.process_batch }.to change(NotificationAudit, :count).by(2)
    end

    it "returns the count of events claimed" do
      create(:webhook_event)
      create(:webhook_event)
      expect(WebhookEventWorker.process_batch).to eq(2)
    end

    it "does not pick up already-processed events" do
      we = create(:webhook_event)
      we.update!(status: "processed")
      expect { WebhookEventWorker.process_batch }.not_to change(NotificationAudit, :count)
    end

    it "marks event as failed when processor raises" do
      we = create(:webhook_event, payload: [ { "event" => "delivered", "email" => "x@x.com", "timestamp" => 1 } ])
      allow(SendgridEventProcessor).to receive(:process).and_raise(StandardError, "boom")
      WebhookEventWorker.process_batch
      expect(we.reload.status).to eq("failed")
      expect(we.failed_reason).to include("StandardError: boom")
    end

    it "returns zero when there are no pending events" do
      expect(WebhookEventWorker.process_batch).to eq(0)
    end
  end
end
