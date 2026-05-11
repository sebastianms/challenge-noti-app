# frozen_string_literal: true

require "rails_helper"

UUID_REGEX = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

RSpec.describe "correlation_id contract", type: :model do
  let(:recipient) { "user@example.com" }

  describe "format" do
    it "matches UUIDv4 pattern on :created result" do
      result = BirthdayNotification.send(recipient, context: { name: "Ana" })
      expect(result.correlation_id).to match(UUID_REGEX)
    end

    it "is nil on :rejected result" do
      result = BirthdayNotification.send("", context: { name: "Ana" })
      expect(result).to be_rejected
      expect(result.correlation_id).to be_nil
    end
  end

  describe "uniqueness" do
    it "generates distinct correlation_ids for distinct events" do
      r1 = BirthdayNotification.send("alice@example.com", context: { name: "Alice" })
      r2 = BirthdayNotification.send("bob@example.com", context: { name: "Bob" })

      expect(r1).to be_created
      expect(r2).to be_created
      expect(r1.correlation_id).not_to eq(r2.correlation_id)
    end
  end

  describe "idempotency" do
    it "returns the original correlation_id for a duplicate within the same window" do
      r1 = BirthdayNotification.send(recipient, context: { name: "Carlos" })
      r2 = BirthdayNotification.send(recipient, context: { name: "Carlos" })

      expect(r1).to be_created
      expect(r2).to be_duplicate
      expect(r2.correlation_id).to eq(r1.correlation_id)
    end
  end
end
