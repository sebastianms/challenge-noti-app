# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::BlacklistCsv do
  describe ".generate" do
    subject(:csv_string) { described_class.generate(items) }

    let(:items) { [ create(:notification_blacklist, :type_scoped, reason: "GDPR request") ] }

    it "includes CSV header row" do
      expect(csv_string).to include("id,recipient_canonical,scope,target,source,reason,created_at")
    end

    it "includes the blacklist entry data" do
      expect(csv_string).to include("type")
      expect(csv_string).to include("birthday")
      expect(csv_string).to include("GDPR request")
    end

    it "returns empty body with only headers for empty list" do
      lines = described_class.generate([]).lines
      expect(lines.size).to eq(1)
      expect(lines.first).to include("id,recipient_canonical")
    end
  end
end
