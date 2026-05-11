# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventBuilder, "blacklist integration" do
  describe "cuando el destinatario está en blacklist" do
    before do
      NotificationBlacklist.create!(
        recipient_canonical: "blocked@example.com",
        scope:               "global",
        source:              "manual",
        reason:              "user requested unsubscribe"
      )
    end

    it "no invoca RulesEngine.decide (corto-circuita pre-reglas)" do
      expect(RulesEngine).not_to receive(:decide)
      BirthdayNotification.send("blocked@example.com")
    end

    it "registra audit con reason=blacklisted y metadata trazable" do
      BirthdayNotification.send("blocked@example.com")

      audit = NotificationAudit.where(recipient_canonical: "blocked@example.com").last
      expect(audit.status).to eq("filtered")
      expect(audit.metadata["reason"]).to eq("blacklisted")
      expect(audit.metadata["scope"]).to eq("global")
      expect(audit.metadata["blacklist_id"]).to be_a(Integer)
    end

    it "no encola en dispatch_queue ni en pending_digests" do
      BirthdayNotification.send("blocked@example.com")

      expect(DispatchQueue.count).to eq(0)
      expect(PendingDigest.count).to eq(0)
    end

    it "retorna SendResult.filtered con correlation_id" do
      result = BirthdayNotification.send("blocked@example.com")
      expect(result).to be_filtered
      expect(result.correlation_id).to match(/\A[\da-f-]{36}\z/)
    end
  end

  describe "cuando el destinatario NO está en blacklist" do
    it "flujo normal: RulesEngine.decide se invoca y el resultado es :created" do
      expect(RulesEngine).to receive(:decide).and_call_original
      result = BirthdayNotification.send("clean@example.com")
      expect(result).to be_created
    end
  end
end
