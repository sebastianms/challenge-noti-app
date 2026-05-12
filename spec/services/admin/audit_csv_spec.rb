# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::AuditCsv do
  describe ".generate" do
    subject(:csv_string) { described_class.generate(items) }

    let(:corr_id) { "a1b2c3d4-0000-0000-0000-000000000001" }
    let(:items) do
      [
        create(:notification_audit, :filtered,
               correlation_id: corr_id,
               channel: "email",
               source: "internal",
               notification_type: "birthday",
               recipient_canonical: "juan@example.com")
      ]
    end

    it "includes CSV header row" do
      expect(csv_string).to include("correlation_id,status,channel,source,notification_type")
    end

    it "includes the audit row data" do
      expect(csv_string).to include(corr_id)
      expect(csv_string).to include("filtered")
      expect(csv_string).to include("birthday")
      expect(csv_string).to include("juan@example.com")
    end

    it "includes reason and rule_id from metadata" do
      expect(csv_string).to include("rate_limited")
    end

    it "returns empty body with only headers for empty list" do
      lines = described_class.generate([]).lines
      expect(lines.size).to eq(1)
      expect(lines.first).to include("correlation_id")
    end
  end
end
