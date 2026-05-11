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

    it "returns an empty array when correlation_id is nil" do
      create(:notification_audit, correlation_id: other_cid)
      expect(AuditSearch.new(correlation_id: nil).call).to eq([])
    end

    it "returns an empty array when correlation_id is blank" do
      create(:notification_audit, correlation_id: other_cid)
      expect(AuditSearch.new(correlation_id: "").call).to eq([])
    end
  end
end
