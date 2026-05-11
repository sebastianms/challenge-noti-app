# frozen_string_literal: true

require "rails_helper"

RSpec.describe SendgridEventProcessor, "blacklist auto-insert" do
  def webhook_with(events)
    create(:webhook_event, payload: events)
  end

  describe "evento bounce con type=bounce (hard)" do
    it "inserta blacklist con source=hard_bounce y reason embebiendo sg_event_id" do
      evt = webhook_with([ {
        "event" => "bounce", "type" => "bounce",
        "email" => "fail@example.com",
        "reason" => "550 5.1.1 mailbox does not exist",
        "sg_event_id" => "evt_abc123"
      } ])

      described_class.process(evt)

      entry = NotificationBlacklist.find_by(recipient_canonical: "fail@example.com")
      expect(entry.source).to eq("hard_bounce")
      expect(entry.scope).to eq("channel")
      expect(entry.target).to eq("email")
      expect(entry.reason).to include("550 5.1.1")
      expect(entry.reason).to include("evt_abc123")
    end
  end

  describe "evento bounce con type=blocked (soft)" do
    it "NO inserta blacklist (solo audit)" do
      evt = webhook_with([ {
        "event" => "bounce", "type" => "blocked",
        "email" => "temp@example.com",
        "reason" => "421 4.2.1 try again later"
      } ])

      described_class.process(evt)

      expect(NotificationBlacklist.where(recipient_canonical: "temp@example.com")).to be_empty
      expect(NotificationAudit.where(recipient_canonical: "temp@example.com", status: "bounced").count).to eq(1)
    end
  end

  describe "eventos dropped / spamreport / deferred" do
    it "dropped inserta blacklist con source=dropped" do
      evt = webhook_with([ { "event" => "dropped", "email" => "drop@example.com", "reason" => "policy" } ])
      described_class.process(evt)
      expect(NotificationBlacklist.find_by(recipient_canonical: "drop@example.com").source).to eq("dropped")
    end

    it "spamreport inserta blacklist con source=spamreport" do
      evt = webhook_with([ { "event" => "spamreport", "email" => "spam@example.com" } ])
      described_class.process(evt)
      expect(NotificationBlacklist.find_by(recipient_canonical: "spam@example.com").source).to eq("spamreport")
    end

    it "deferred NO inserta blacklist" do
      evt = webhook_with([ { "event" => "deferred", "email" => "defer@example.com" } ])
      described_class.process(evt)
      expect(NotificationBlacklist.where(recipient_canonical: "defer@example.com")).to be_empty
    end
  end

  describe "idempotencia ON CONFLICT" do
    it "un segundo evento idéntico no duplica la fila" do
      payload = [ { "event" => "bounce", "type" => "bounce", "email" => "dup@example.com", "reason" => "550" } ]
      described_class.process(webhook_with(payload))
      described_class.process(webhook_with(payload))

      expect(NotificationBlacklist.where(recipient_canonical: "dup@example.com").count).to eq(1)
    end
  end

  describe "transaccionalidad audit + blacklist" do
    it "si el insert de blacklist falla, el audit roll-backea" do
      evt = webhook_with([ { "event" => "bounce", "type" => "bounce", "email" => "tx@example.com", "reason" => "x" } ])
      allow(NotificationBlacklist).to receive(:insert_all).and_raise(ActiveRecord::StatementInvalid, "boom")

      expect { described_class.process(evt) }.to raise_error(ActiveRecord::StatementInvalid)

      expect(NotificationAudit.where(recipient_canonical: "tx@example.com")).to be_empty
    end
  end
end
