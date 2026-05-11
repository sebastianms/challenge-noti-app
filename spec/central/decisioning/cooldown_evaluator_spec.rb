# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe CooldownEvaluator do
  let(:event) { OpenStruct.new(notification_type: "welcome", recipient_canonical: "a@b.com") }
  let(:rule)  { NotificationRule.new(notification_type: "welcome", cooldown_seconds: 60) }

  def audit_with(seconds_ago:)
    create(:notification_audit,
           notification_type:   "welcome",
           recipient_canonical: "a@b.com",
           status:              "delivered",
           created_at:          seconds_ago.seconds.ago)
  end

  it "returns false when cooldown_seconds is nil" do
    rule.cooldown_seconds = nil
    expect(described_class.in_cooldown?(rule, event)).to be false
  end

  it "returns false when there are no previous audits" do
    expect(described_class.in_cooldown?(rule, event)).to be false
  end

  it "returns true when the last audit is within the cooldown window" do
    audit_with(seconds_ago: 30)
    expect(described_class.in_cooldown?(rule, event)).to be true
  end

  it "returns false when the last audit is older than cooldown" do
    audit_with(seconds_ago: 120)
    expect(described_class.in_cooldown?(rule, event)).to be false
  end

  it "ignores audits for a different recipient" do
    create(:notification_audit,
           notification_type:   "welcome",
           recipient_canonical: "other@b.com",
           status:              "delivered",
           created_at:          30.seconds.ago)
    expect(described_class.in_cooldown?(rule, event)).to be false
  end
end
