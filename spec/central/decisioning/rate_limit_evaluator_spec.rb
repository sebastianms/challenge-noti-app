# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe RateLimitEvaluator do
  let(:event)     { OpenStruct.new(notification_type: "welcome", recipient_canonical: "a@b.com") }
  let(:rule)      { NotificationRule.new(notification_type: "welcome", max_per_day: 3) }

  def audit_with(status:, hours_ago: 0)
    create(:notification_audit,
           notification_type:   "welcome",
           recipient_canonical: "a@b.com",
           status:              status,
           created_at:          hours_ago.hours.ago)
  end

  it "returns false when max_per_day is nil" do
    rule.max_per_day = nil
    expect(described_class.exceeded?(rule, event)).to be false
  end

  it "returns false when count is below max_per_day" do
    2.times { audit_with(status: "delivered") }
    expect(described_class.exceeded?(rule, event)).to be false
  end

  it "returns true when count reaches max_per_day" do
    3.times { audit_with(status: "delivered") }
    expect(described_class.exceeded?(rule, event)).to be true
  end

  it "ignores audits outside the 24h window" do
    3.times { audit_with(status: "delivered", hours_ago: 25) }
    expect(described_class.exceeded?(rule, event)).to be false
  end

  it "only counts enqueued/dispatched/delivered statuses" do
    3.times { audit_with(status: "filtered") }
    expect(described_class.exceeded?(rule, event)).to be false
  end

  it "ignores audits for other recipients" do
    3.times do
      create(:notification_audit,
             notification_type:   "welcome",
             recipient_canonical: "other@b.com",
             status:              "delivered")
    end
    expect(described_class.exceeded?(rule, event)).to be false
  end
end
