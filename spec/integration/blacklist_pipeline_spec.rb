# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Blacklist pipeline", type: :integration do
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
end
