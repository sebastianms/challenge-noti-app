# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::DashboardMetrics, type: :service do
  subject(:service) { described_class.new }

  before { Rails.cache.clear }

  describe "#snapshot keys" do
    it "returns all expected keys" do
      expect(service.snapshot.keys).to match_array(%i[volume filter_rate error_rate queue_depth dlq_depth volume_by_type volume_by_channel])
    end
  end

  describe "empty state" do
    it "returns empty volume" do
      expect(service.snapshot[:volume]).to be_a(Hash)
    end

    it "returns empty filter_rate" do
      expect(service.snapshot[:filter_rate]).to eq({})
    end

    it "returns empty error_rate" do
      expect(service.snapshot[:error_rate]).to eq({})
    end

    it "returns zero queue_depth" do
      expect(service.snapshot[:queue_depth]).to eq(0)
    end

    it "returns zero dlq_depth" do
      expect(service.snapshot[:dlq_depth]).to eq(0)
    end
  end

  describe "with data" do
    before do
      create_list(:notification_event, 3)
      create(:notification_audit, :delivered)
      create(:notification_audit, :failed, notification_type: "birthday")
      create(:notification_audit, :failed, notification_type: "birthday")
      create(:notification_audit, :filtered)
    end

    it "counts events in volume" do
      total = service.snapshot[:volume].values.sum
      expect(total).to eq(3)
    end

    it "groups filter_rate by status" do
      rates = service.snapshot[:filter_rate]
      expect(rates["delivered"]).to eq(1)
      expect(rates["filtered"]).to eq(1)
    end

    it "counts errors by notification_type" do
      expect(service.snapshot[:error_rate]["birthday"]).to eq(2)
    end
  end

  describe "queue depth (live, not cached)" do
    it "reflects pending dispatch queue entries" do
      create(:dispatch_queue, status: "pending")
      create(:dispatch_queue, status: "pending")
      expect(service.snapshot[:queue_depth]).to eq(2)
    end

    it "reflects failed dispatch queue entries (dlq)" do
      create(:dispatch_queue, status: "failed")
      expect(service.snapshot[:dlq_depth]).to eq(1)
    end

    it "queue_depth updates without clearing cache" do
      snap1 = service.snapshot
      create(:dispatch_queue, status: "pending")
      snap2 = described_class.new.snapshot
      expect(snap2[:queue_depth]).to eq(snap1[:queue_depth] + 1)
    end
  end

  describe "cache hit" do
    around do |example|
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = original
    end

    it "returns the same volume on second call without new DB query" do
      create(:notification_event)
      snap1 = service.snapshot[:volume]
      create(:notification_event)
      snap2 = described_class.new.snapshot[:volume]
      # Second call should hit cache — count stays the same
      expect(snap2.values.sum).to eq(snap1.values.sum)
    end
  end
end
