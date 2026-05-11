# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuditSearch do
  describe "#call (correlation_id mode)" do
    let(:target_cid) { SecureRandom.uuid }
    let(:other_cid)  { SecureRandom.uuid }

    it "returns all audits for the correlation_id ordered by created_at ASC" do
      create(:notification_audit, correlation_id: target_cid, status: "enqueued",   created_at: 3.minutes.ago)
      create(:notification_audit, correlation_id: target_cid, status: "dispatched", created_at: 2.minutes.ago)
      create(:notification_audit, correlation_id: target_cid, status: "delivered",  created_at: 1.minute.ago)
      5.times { create(:notification_audit, correlation_id: other_cid) }

      result = AuditSearch.new(correlation_id: target_cid).call

      expect(result.map(&:status)).to eq(%w[enqueued dispatched delivered])
    end

    it "returns an empty array when no audits match" do
      create(:notification_audit, correlation_id: other_cid)
      expect(AuditSearch.new(correlation_id: SecureRandom.uuid).call).to eq([])
    end
  end

  describe "#call (filter mode)" do
    it "filters by recipient_canonical" do
      create(:notification_audit, :with_recipient, recipient_canonical: "alice@example.com")
      create(:notification_audit, :with_recipient, recipient_canonical: "bob@example.com")
      result = AuditSearch.new(recipient: "alice@example.com").call
      expect(result.total).to eq(1)
      expect(result.items.first.recipient_canonical).to eq("alice@example.com")
    end

    it "filters by status" do
      create(:notification_audit, status: "delivered")
      create(:notification_audit, status: "failed")
      result = AuditSearch.new(status: "failed").call
      expect(result.total).to eq(1)
    end

    it "filters by source" do
      create(:notification_audit, source: "internal")
      create(:notification_audit, :from_webhook)
      result = AuditSearch.new(source: "sendgrid_webhook").call
      expect(result.total).to eq(1)
    end

    it "filters by date range (from/to)" do
      create(:notification_audit, created_at: 2.days.ago)
      create(:notification_audit, created_at: 1.hour.ago)
      result = AuditSearch.new(from: 1.day.ago, to: Time.current).call
      expect(result.total).to eq(1)
    end

    it "combines filters with AND semantics" do
      create(:notification_audit, status: "failed", recipient_canonical: "x@x.com")
      create(:notification_audit, status: "failed", recipient_canonical: "y@y.com")
      create(:notification_audit, status: "delivered", recipient_canonical: "x@x.com")
      result = AuditSearch.new(status: "failed", recipient: "x@x.com").call
      expect(result.total).to eq(1)
    end

    it "paginates with LIMIT/OFFSET ordered DESC by created_at" do
      60.times { |i| create(:notification_audit, status: "failed", created_at: i.minutes.ago) }
      page1 = AuditSearch.new(status: "failed", page: 1, per_page: 50).call
      page2 = AuditSearch.new(status: "failed", page: 2, per_page: 50).call

      expect(page1.total).to eq(60)
      expect(page1.items.size).to eq(50)
      expect(page1.has_next?).to be true
      expect(page2.items.size).to eq(10)
      expect(page2.has_next?).to be false
    end

    it "caps per_page at MAX_PER_PAGE (50)" do
      result = AuditSearch.new(per_page: 999).call
      expect(result.per_page).to eq(50)
    end

    it "orders results by created_at DESC" do
      old = create(:notification_audit, created_at: 2.hours.ago)
      new = create(:notification_audit, created_at: 1.minute.ago)
      result = AuditSearch.new.call
      expect(result.items.first.correlation_id).to eq(new.correlation_id)
      expect(result.items.last.correlation_id).to eq(old.correlation_id)
    end
  end
end
