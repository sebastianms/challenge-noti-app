# frozen_string_literal: true

require "rails_helper"

RSpec.describe DigestScheduler, type: :model do
  describe ".process_batch" do
    it "returns zero when there are no pending digests" do
      expect(described_class.process_batch).to eq(0)
    end

    it "ignores items whose dispatch_at is in the future" do
      create(:pending_digest, :future)
      expect(described_class.process_batch).to eq(0)
      expect(DispatchQueue.count).to eq(0)
    end

    it "consolidates a single group into one DispatchQueue row" do
      3.times { create(:pending_digest, :ready, notification_type: "welcome", recipient_canonical: "a@b.com") }

      groups = described_class.process_batch
      expect(groups).to eq(1)
      expect(DispatchQueue.count).to eq(1)
    end

    it "marks consolidated rows with consolidated_into uuid" do
      2.times { create(:pending_digest, :ready) }
      described_class.process_batch
      expect(PendingDigest.where(status: "consolidated").count).to eq(2)
      expect(PendingDigest.first.consolidated_into).to be_present
    end

    it "groups by (notification_type, recipient_canonical)" do
      2.times { create(:pending_digest, :ready, notification_type: "welcome", recipient_canonical: "a@b.com") }
      2.times { create(:pending_digest, :ready, notification_type: "welcome", recipient_canonical: "b@b.com") }
      2.times { create(:pending_digest, :ready, notification_type: "mention", recipient_canonical: "a@b.com") }

      groups = described_class.process_batch
      expect(groups).to eq(3)
      expect(DispatchQueue.count).to eq(3)
    end

    it "creates digested audit for each item and enqueued audit for the digest" do
      3.times { create(:pending_digest, :ready, notification_type: "welcome", recipient_canonical: "a@b.com") }
      described_class.process_batch

      expect(NotificationAudit.where(status: "digested").count).to eq(3)
      expect(NotificationAudit.where(status: "enqueued").where("metadata->>'digest' = 'true'").count).to eq(1)
    end

    it "fuses payloads under digest_items key" do
      create(:pending_digest, :ready, notification_type: "welcome", recipient_canonical: "a@b.com", payload: { "msg" => "1" })
      create(:pending_digest, :ready, notification_type: "welcome", recipient_canonical: "a@b.com", payload: { "msg" => "2" })
      described_class.process_batch

      digest_audit = NotificationAudit.where("metadata->>'digest' = 'true'").first
      expect(digest_audit.payload["digest_items"].size).to eq(2)
    end

    it "uses SKIP LOCKED so two threads do not consolidate the same items", :threads do
      6.times { create(:pending_digest, :ready, notification_type: "welcome", recipient_canonical: "a@b.com") }

      threads = 2.times.map { Thread.new { described_class.process_batch(batch_size: 6) } }
      threads.each(&:join)

      expect(PendingDigest.where(status: "consolidated").count).to eq(6)
      expect(DispatchQueue.count).to eq(1).or eq(2)
    end
  end
end
