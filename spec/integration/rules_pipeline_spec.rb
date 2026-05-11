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
end
