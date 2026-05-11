# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::SendgridEventsController, type: :request do
  let(:keypair)   { SendgridWebhookSigner.generate_keypair }
  let(:timestamp) { Time.current.to_i.to_s }
  let(:events)    { [ SendgridWebhookSigner.delivered_event ] }
  let(:body)      { events.to_json }
  let(:signature) { SendgridWebhookSigner.sign(payload: body, timestamp: timestamp, signing_key: keypair[:signing_key]) }

  before do
    ENV["SENDGRID_WEBHOOK_PUBLIC_KEY"] = keypair[:public_key_b64]
  end

  after do
    ENV.delete("SENDGRID_WEBHOOK_PUBLIC_KEY")
  end

  def post_webhook(body:, signature:, timestamp:)
    post "/webhooks/sendgrid",
         params:  body,
         headers: {
           "Content-Type"                                   => "application/json",
           "X-Twilio-Email-Event-Webhook-Signature"         => signature,
           "X-Twilio-Email-Event-Webhook-Timestamp"         => timestamp
         }
  end

  it "returns 200 and persists a webhook_event with valid signature" do
    expect {
      post_webhook(body: body, signature: signature, timestamp: timestamp)
    }.to change(WebhookEvent, :count).by(1)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["received"]).to eq(1)
  end

  it "returns 401 with an invalid signature" do
    post_webhook(body: body, signature: "BAD_SIG", timestamp: timestamp)
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 401 when signature headers are missing" do
    post "/webhooks/sendgrid", params: body, headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 400 for unparseable JSON" do
    bad_body = "{not-json"
    bad_sig  = SendgridWebhookSigner.sign(payload: bad_body, timestamp: timestamp, signing_key: keypair[:signing_key])
    post_webhook(body: bad_body, signature: bad_sig, timestamp: timestamp)
    expect(response).to have_http_status(:bad_request)
  end

  it "does not process events inline (status remains pending)" do
    post_webhook(body: body, signature: signature, timestamp: timestamp)
    expect(WebhookEvent.last.status).to eq("pending")
  end

  it "returns 503 when public key is not configured" do
    ENV.delete("SENDGRID_WEBHOOK_PUBLIC_KEY")
    post_webhook(body: body, signature: signature, timestamp: timestamp)
    expect(response).to have_http_status(:service_unavailable)
  end
end
