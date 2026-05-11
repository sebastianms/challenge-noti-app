# frozen_string_literal: true

require "rails_helper"

RSpec.describe IdempotencyHash do
  let(:base_args) do
    {
      notification_type:   "birthday",
      recipient_canonical: "juan@example.com",
      context_id:          "no_context",
      window_ts:           Time.utc(2026, 5, 10, 10, 0, 0)
    }
  end

  describe ".compute" do
    it "es determinista: mismos inputs producen mismo hash" do
      h1 = described_class.compute(**base_args)
      h2 = described_class.compute(**base_args)
      expect(h1).to eq(h2)
    end

    it "tiene formato SHA256 (64 chars hex)" do
      hash = described_class.compute(**base_args)
      expect(hash).to match(/\A[a-f0-9]{64}\z/)
    end

    it "cambia si cambia notification_type" do
      h1 = described_class.compute(**base_args)
      h2 = described_class.compute(**base_args.merge(notification_type: "invoice_paid"))
      expect(h1).not_to eq(h2)
    end

    it "cambia si cambia recipient_canonical" do
      h1 = described_class.compute(**base_args)
      h2 = described_class.compute(**base_args.merge(recipient_canonical: "otro@example.com"))
      expect(h1).not_to eq(h2)
    end

    it "cambia si cambia context_id" do
      h1 = described_class.compute(**base_args)
      h2 = described_class.compute(**base_args.merge(context_id: "42"))
      expect(h1).not_to eq(h2)
    end

    it "cambia si cambia window_ts" do
      h1 = described_class.compute(**base_args)
      h2 = described_class.compute(**base_args.merge(window_ts: Time.utc(2026, 5, 10, 11, 0, 0)))
      expect(h1).not_to eq(h2)
    end
  end
end
