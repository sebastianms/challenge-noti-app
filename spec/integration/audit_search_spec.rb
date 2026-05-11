# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AuditSearch integration", type: :model do
  before do
    20.times do |i|
      create(:notification_audit,
             status:              "failed",
             recipient_canonical: "a@example.com",
             source:              "internal",
             created_at:          (i + 1).hours.ago)
    end
    20.times do |i|
      create(:notification_audit,
             status:              "delivered",
             recipient_canonical: "b@example.com",
             source:              "sendgrid_webhook",
             created_at:          (i + 1).hours.ago)
    end
    20.times do |i|
      create(:notification_audit,
             status:              "enqueued",
             recipient_canonical: "c@example.com",
             source:              "internal",
             created_at:          (i + 1).hours.ago)
    end
  end

  it "paginates 60 records across 2 pages with page 1 returning 50 and page 2 returning 10" do
    p1 = AuditSearch.new(page: 1, per_page: 50).call
    p2 = AuditSearch.new(page: 2, per_page: 50).call
    expect(p1.total).to eq(60)
    expect(p1.items.size).to eq(50)
    expect(p2.items.size).to eq(10)
  end

  it "filters by recipient AND status with correct cardinality" do
    result = AuditSearch.new(recipient: "a@example.com", status: "failed").call
    expect(result.total).to eq(20)
  end

  it "filters by source returns only webhook-sourced rows" do
    result = AuditSearch.new(source: "sendgrid_webhook").call
    expect(result.total).to eq(20)
    expect(result.items.map(&:source).uniq).to eq([ "sendgrid_webhook" ])
  end

  it "orders results DESC by created_at across the full result set" do
    result = AuditSearch.new(per_page: 50).call
    timestamps = result.items.map(&:created_at)
    expect(timestamps).to eq(timestamps.sort.reverse)
  end
end
