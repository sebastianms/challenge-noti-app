# frozen_string_literal: true

require "rails_helper"

RSpec.describe SendgridEventProcessor do
  describe ".process" do
    it "translates 'delivered' to status delivered" do
      we = create(:webhook_event, payload: [ SendgridWebhookSigner.delivered_event ])
      expect { described_class.process(we) }.to change(NotificationAudit, :count).by(1)
      expect(NotificationAudit.last.status).to eq("delivered")
    end

    it "translates 'bounce' to status bounced" do
      we = create(:webhook_event, payload: [ SendgridWebhookSigner.bounce_event ])
      described_class.process(we)
      expect(NotificationAudit.last.status).to eq("bounced")
    end

    it "translates 'spamreport' to status spam_reported" do
      we = create(:webhook_event, payload: [ SendgridWebhookSigner.spam_event ])
      described_class.process(we)
      expect(NotificationAudit.last.status).to eq("spam_reported")
    end

    it "falls back to status 'raw' for unknown event types" do
      we = create(:webhook_event, payload: [ { "event" => "unknown_event", "email" => "x@x.com", "timestamp" => 1 } ])
      described_class.process(we)
      expect(NotificationAudit.last.status).to eq("raw")
    end

    it "populates recipient_canonical from event.email and source=sendgrid_webhook" do
      we = create(:webhook_event, payload: [ SendgridWebhookSigner.delivered_event(email: "alice@example.com") ])
      described_class.process(we)
      a = NotificationAudit.last
      expect(a.recipient_canonical).to eq("alice@example.com")
      expect(a.source).to eq("sendgrid_webhook")
    end

    it "stores type and sg_timestamp in metadata" do
      evt = SendgridWebhookSigner.bounce_event(bounce_type: "hard")
      we  = create(:webhook_event, payload: [ evt ])
      described_class.process(we)
      meta = NotificationAudit.last.metadata
      expect(meta["type"]).to eq("bounce")
      expect(meta["sg_timestamp"]).to eq(evt["timestamp"])
    end
  end
end
