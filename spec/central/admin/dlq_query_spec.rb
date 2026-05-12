# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::DlqQuery do
  describe ".grouped_by_reason" do
    it "groups dead jobs by error class" do
      create(:dispatch_queue, :failed, failed_reason: "Net::OpenTimeout: execution expired")
      create(:dispatch_queue, :failed, failed_reason: "Net::OpenTimeout: too slow")
      create(:dispatch_queue, :failed, failed_reason: "SendgridAdapter: 503")

      groups = described_class.grouped_by_reason
      reason_classes = groups.map { |g| g[:reason_class] }
      expect(reason_classes).to include("Net", "SendgridAdapter")

      timeout_group = groups.find { |g| g[:reason_class].start_with?("Net") }
      expect(timeout_group[:count]).to eq(2)
    end

    it "returns Unknown for jobs with blank failed_reason" do
      create(:dispatch_queue, :failed, failed_reason: nil)

      groups = described_class.grouped_by_reason
      expect(groups.map { |g| g[:reason_class] }).to include("Unknown")
    end

    it "filters by reason when reason_filter is provided" do
      create(:dispatch_queue, :failed, failed_reason: "Net::OpenTimeout: slow")
      create(:dispatch_queue, :failed, failed_reason: "SendgridAdapter: 503")

      groups = described_class.grouped_by_reason(reason_filter: "Net")
      expect(groups.size).to eq(1)
      expect(groups.first[:reason_class]).to start_with("Net")
    end

    it "caps items_preview at ITEMS_PREVIEW_CAP" do
      (Admin::DlqQuery::ITEMS_PREVIEW_CAP + 2).times do
        create(:dispatch_queue, :failed, failed_reason: "Net::OpenTimeout: x")
      end

      groups = described_class.grouped_by_reason
      group = groups.find { |g| g[:reason_class].start_with?("Net") }
      expect(group[:items].size).to eq(Admin::DlqQuery::ITEMS_PREVIEW_CAP)
    end

    it "excludes non-failed jobs" do
      create(:dispatch_queue, :done)
      create(:dispatch_queue)

      groups = described_class.grouped_by_reason
      expect(groups).to be_empty
    end
  end

  describe ".reason_class_for" do
    it "extracts class before first colon" do
      expect(described_class.reason_class_for("Net::OpenTimeout: msg")).to eq("Net")
    end

    it "returns Unknown for blank input" do
      expect(described_class.reason_class_for(nil)).to eq("Unknown")
      expect(described_class.reason_class_for("")).to eq("Unknown")
    end
  end
end
