# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Blacklist pipeline", type: :request do
  describe "US1a — scope=global filtra cualquier tipo y casing distinto" do
    before do
      NotificationBlacklist.create!(
        recipient_canonical: "blocked@example.com",
        scope:               "global",
        source:              "manual",
        reason:              "user requested unsubscribe via support ticket #42"
      )
    end

    it "filtra envío con casing distinto y registra audit con reason=blacklisted" do
      result = BirthdayNotification.send("Blocked@Example.com")

      expect(result).to be_filtered
      expect(result.correlation_id).to match(/\A[\da-f-]{36}\z/)

      audit = NotificationAudit.where(recipient_canonical: "blocked@example.com").last
      expect(audit.status).to eq("filtered")
      expect(audit.metadata["reason"]).to eq("blacklisted")
      expect(audit.metadata["scope"]).to eq("global")

      expect(DispatchQueue.count).to eq(0)
    end
  end

  describe "US1b — scope=type aísla bloqueo por notification_type" do
    before do
      NotificationBlacklist.create!(
        recipient_canonical: "selective@example.com",
        scope:               "type",
        target:              "birthday",
        source:              "manual",
        reason:              "no birthday messages"
      )
    end

    it "filtra el tipo bloqueado y deja pasar otros tipos" do
      blocked = BirthdayNotification.send("selective@example.com")
      allowed = InvoicePaidNotification.send("selective@example.com", context: { invoice_id: 1 })

      expect(blocked).to be_filtered
      expect(allowed).to be_created
    end
  end

  describe "US1c — scope=channel filtra envíos por canal" do
    before do
      NotificationBlacklist.create!(
        recipient_canonical: "channel@example.com",
        scope:               "channel",
        target:              "email",
        source:              "manual",
        reason:              "unsubscribed from email"
      )
    end

    it "filtra envíos por email cuando el destinatario tiene scope=channel email" do
      result = BirthdayNotification.send("channel@example.com")
      expect(result).to be_filtered

      audit = NotificationAudit.where(recipient_canonical: "channel@example.com").last
      expect(audit.metadata["scope"]).to eq("channel")
      expect(audit.metadata["target"]).to eq("email")
    end
  end

  describe "edge case — canonicalization coherente entre insert y lookup" do
    it "matchea aunque el caller pase recipient con uppercase/whitespace" do
      NotificationBlacklist.create!(
        recipient_canonical: "edge@example.com",
        scope:               "global",
        source:              "manual"
      )

      result = BirthdayNotification.send("  EDGE@Example.com  ")
      expect(result).to be_filtered
    end
  end

  describe "US3 — alta y remoción via UI deja audit trail" do
    let(:headers) do
      { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "admin") }
    end

    it "create via POST → listed en index → destroy via DELETE → audit blacklist_removed visible" do
      post "/admin/blacklist",
           params:  { recipient: "ui@example.com", scope: "global", reason: "from form" },
           headers: headers
      expect(response).to have_http_status(:see_other)

      get "/admin/blacklist", headers: headers
      expect(response.body).to include("ui@example.com")

      entry = NotificationBlacklist.find_by(recipient_canonical: "ui@example.com")
      delete "/admin/blacklist/#{entry.id}",
             params:  { reason: "reactivated" },
             headers: headers
      expect(response).to have_http_status(:see_other)
      expect(NotificationBlacklist.find_by(id: entry.id)).to be_nil

      audit = NotificationAudit.find_by(notification_type: "_blacklist_removed_")
      expect(audit.metadata["removed_by"]).to eq("admin")
      expect(audit.metadata["reason"]).to eq("reactivated")
    end
  end

  describe "US2 — POST webhook hard bounce → blacklist → siguiente envío filtered" do
    let(:keypair)   { SendgridWebhookSigner.generate_keypair }
    let(:timestamp) { Time.current.to_i.to_s }
    let(:hard_bounce) do
      {
        "event"       => "bounce",
        "type"        => "bounce",
        "email"       => "willfail@example.com",
        "reason"      => "550 5.1.1 mailbox does not exist",
        "timestamp"   => Time.current.to_i,
        "sg_event_id" => "evt_hard_001"
      }
    end
    let(:body)      { [ hard_bounce ].to_json }
    let(:signature) { SendgridWebhookSigner.sign(payload: body, timestamp: timestamp, signing_key: keypair[:signing_key]) }

    before  { ENV["SENDGRID_WEBHOOK_PUBLIC_KEY"] = keypair[:public_key_b64] }
    after   { ENV.delete("SENDGRID_WEBHOOK_PUBLIC_KEY") }

    it "POST firmado + process_batch → blacklist creada + siguiente .send filtered" do
      post "/webhooks/sendgrid",
           params:  body,
           headers: {
             "Content-Type"                           => "application/json",
             "X-Twilio-Email-Event-Webhook-Signature" => signature,
             "X-Twilio-Email-Event-Webhook-Timestamp" => timestamp
           }
      expect(response).to have_http_status(:ok)

      WebhookEventWorker.process_batch

      entry = NotificationBlacklist.find_by(recipient_canonical: "willfail@example.com")
      expect(entry).not_to be_nil
      expect(entry.source).to eq("hard_bounce")

      result = BirthdayNotification.send("willfail@example.com")
      expect(result).to be_filtered
    end
  end
end
