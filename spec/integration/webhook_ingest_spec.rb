# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Webhook ingest end-to-end", type: :request do
  let(:keypair)   { SendgridWebhookSigner.generate_keypair }
  let(:timestamp) { Time.current.to_i.to_s }
  let(:events) do
    [
      SendgridWebhookSigner.delivered_event(email: "ok@example.com"),
      SendgridWebhookSigner.bounce_event(email: "bad@example.com"),
      SendgridWebhookSigner.spam_event(email: "spam@example.com")
    ]
  end
  let(:body)      { events.to_json }
  let(:signature) { SendgridWebhookSigner.sign(payload: body, timestamp: timestamp, signing_key: keypair[:signing_key]) }

  before do
    ENV["SENDGRID_WEBHOOK_PUBLIC_KEY"] = keypair[:public_key_b64]
  end

  after do
    ENV.delete("SENDGRID_WEBHOOK_PUBLIC_KEY")
  end

  def post_signed
    post "/webhooks/sendgrid",
         params:  body,
         headers: {
           "Content-Type"                            => "application/json",
           "X-Twilio-Email-Event-Webhook-Signature"  => signature,
           "X-Twilio-Email-Event-Webhook-Timestamp"  => timestamp
         }
  end

  it "POST signed webhook responds 200" do
    post_signed
    expect(response).to have_http_status(:ok)
  end

  it "creates a pending webhook_event row" do
    post_signed
    expect(WebhookEvent.last.status).to eq("pending")
    expect(WebhookEvent.last.payload.size).to eq(3)
  end

  it "WebhookEventWorker processes the batch and marks event processed" do
    post_signed
    WebhookEventWorker.process_batch
    expect(WebhookEvent.last.status).to eq("processed")
  end

  it "creates NotificationAudit entries with source=sendgrid_webhook" do
    post_signed
    WebhookEventWorker.process_batch
    audits = NotificationAudit.where(source: "sendgrid_webhook")
    expect(audits.count).to eq(3)
  end

  it "maps event types to correct statuses (delivered/bounced/spam_reported)" do
    post_signed
    WebhookEventWorker.process_batch
    statuses = NotificationAudit.where(source: "sendgrid_webhook").pluck(:status)
    expect(statuses).to match_array(%w[delivered bounced spam_reported])
  end
end
