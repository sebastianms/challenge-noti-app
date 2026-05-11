# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rules engine pipeline" do
  before do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  after { Rails.cache = @original_cache }

  describe "rate limit fuerza filtered (US1 Scenario 1)" do
    it "creates 1 enqueued and 2 filtered when sending 3 with max_per_day=1" do
      NotificationRule.create!(notification_type: "birthday", max_per_day: 1, channels: [ "email" ])

      3.times { BirthdayNotification.send("juan@example.com", context: { id: SecureRandom.uuid, name: "Juan" }) }

      audits = NotificationAudit.where(recipient_canonical: "juan@example.com")
      expect(audits.where(status: "enqueued").count).to eq(1)
      expect(audits.where(status: "filtered").count).to eq(2)
      expect(audits.where(status: "filtered").first.metadata["reason"]).to eq("rate_limited")
    end
  end

  describe "canal deshabilitado (US1 Scenario 2)" do
    it "filters with reason=disabled and does not enqueue" do
      NotificationRule.create!(notification_type: "birthday", channels: [])

      BirthdayNotification.send("juan@example.com", context: { id: "x1", name: "Juan" })

      expect(NotificationAudit.last.status).to eq("filtered")
      expect(NotificationAudit.last.metadata["reason"]).to eq("disabled")
      expect(DispatchQueue.count).to eq(0)
    end
  end

  describe "compatibilidad sin regla (US1 Scenario 3)" do
    it "dispatches without restrictions when no rule exists for the type" do
      BirthdayNotification.send("juan@example.com", context: { id: "x2", name: "Juan" })

      expect(DispatchQueue.count).to eq(1)
      expect(NotificationAudit.where(status: "enqueued").count).to eq(1)
      expect(NotificationAudit.last.metadata).to be_nil
    end
  end

  describe "edición en caliente (US3 Scenario 5)" do
    it "applies the updated rule on the very next send after rule.update!" do
      rule = NotificationRule.create!(notification_type: "birthday", max_per_day: 3, channels: [ "email" ])

      3.times { |i| BirthdayNotification.send("juan@example.com", context: { id: "h#{i}", name: "Juan" }) }
      expect(NotificationAudit.where(status: "enqueued").count).to eq(3)

      rule.update!(max_per_day: 1)

      BirthdayNotification.send("juan@example.com", context: { id: "h_new", name: "Juan" })

      filtered = NotificationAudit.where(status: "filtered").last
      expect(filtered.metadata["reason"]).to eq("rate_limited")
      expect(filtered.metadata["rule_id"]).to eq(rule.id)
    end

    it "after_destroy on a rule removes it from cache immediately" do
      rule = NotificationRule.create!(notification_type: "birthday", channels: [])
      BirthdayNotification.send("juan@example.com", context: { id: "d1" })
      expect(NotificationAudit.last.status).to eq("filtered")

      rule.destroy

      BirthdayNotification.send("juan@example.com", context: { id: "d2" })
      expect(NotificationAudit.last.status).to eq("enqueued")
    end
  end

  describe "cache hit rate (US3 Scenario 7, SC-002)" do
    it "hits notification_rules at most once for many sends of the same type" do
      NotificationRule.create!(notification_type: "birthday", channels: [ "email" ])

      query_count = 0
      callback = ->(*, payload) { query_count += 1 if payload[:sql]&.include?("notification_rules") }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        20.times { |i| BirthdayNotification.send("u#{i}@example.com", context: { id: "c#{i}", name: "U#{i}" }) }
      end

      expect(query_count).to be <= 1
    end
  end

  describe "audit con rule_id y reason (US4 Scenario 6)" do
    it "populates rule_id and reason in metadata for filtered rows" do
      rule = NotificationRule.create!(notification_type: "birthday", channels: [])
      BirthdayNotification.send("juan@example.com", context: { id: "f1", name: "Juan" })

      audit = NotificationAudit.last
      expect(audit.metadata["rule_id"]).to eq(rule.id)
      expect(audit.metadata["reason"]).to eq("disabled")
    end

    it "populates rule_id in metadata for rate_limited rows" do
      rule = NotificationRule.create!(notification_type: "birthday", max_per_day: 1, channels: [ "email" ])
      2.times { |i| BirthdayNotification.send("alice@example.com", context: { id: "r#{i}", name: "Alice" }) }

      filtered = NotificationAudit.where(status: "filtered").first
      expect(filtered.metadata["rule_id"]).to eq(rule.id)
      expect(filtered.metadata["reason"]).to eq("rate_limited")
    end
  end

  describe "digest end-to-end (US2 Scenario 4)" do
    it "accumulates pending_digests and consolidates after the window expires" do
      NotificationRule.create!(notification_type: "birthday", digest_window_seconds: 60, channels: [ "email" ])

      5.times { |i| BirthdayNotification.send("alice@example.com", context: { id: "d#{i}", name: "Alice" }) }

      expect(PendingDigest.where(status: "pending").count).to eq(5)
      expect(DispatchQueue.count).to eq(0)

      PendingDigest.update_all(dispatch_at: 1.second.ago)
      DigestScheduler.process_batch

      expect(DispatchQueue.count).to eq(1)
      expect(PendingDigest.where(status: "consolidated").count).to eq(5)
      expect(NotificationAudit.where(status: "digested").count).to eq(5)
    end
  end
end
