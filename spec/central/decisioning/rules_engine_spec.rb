# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe RulesEngine do
  let(:event) { OpenStruct.new(notification_type: "welcome", recipient_canonical: "a@b.com") }

  before do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  after { Rails.cache = @original_cache }

  it "returns dispatch when no rule exists" do
    decision = described_class.decide(event: event)
    expect(decision).to be_dispatch
    expect(decision.rule_id).to be_nil
  end

  it "returns dispatch when the rule is disabled (treated as no rule)" do
    NotificationRule.create!(notification_type: "welcome", enabled: false, channels: [])
    decision = described_class.decide(event: event)
    expect(decision).to be_dispatch
  end

  it "filters with reason=disabled when channels is empty array" do
    rule = NotificationRule.create!(notification_type: "welcome", channels: [])
    decision = described_class.decide(event: event)
    expect(decision).to be_filter
    expect(decision.reason).to eq("disabled")
    expect(decision.rule_id).to eq(rule.id)
  end

  it "filters with reason=rate_limited when rate limit is exceeded" do
    rule = NotificationRule.create!(notification_type: "welcome", max_per_day: 1)
    create(:notification_audit, notification_type: "welcome", recipient_canonical: "a@b.com", status: "delivered")
    decision = described_class.decide(event: event)
    expect(decision).to be_filter
    expect(decision.reason).to eq("rate_limited")
    expect(decision.rule_id).to eq(rule.id)
  end

  it "filters with reason=cooldown when in cooldown" do
    rule = NotificationRule.create!(notification_type: "welcome", cooldown_seconds: 60)
    create(:notification_audit,
           notification_type:   "welcome",
           recipient_canonical: "a@b.com",
           status:              "delivered",
           created_at:          30.seconds.ago)
    decision = described_class.decide(event: event)
    expect(decision).to be_filter
    expect(decision.reason).to eq("cooldown")
    expect(decision.rule_id).to eq(rule.id)
  end

  it "returns digest when digest_window_seconds is set" do
    rule = NotificationRule.create!(notification_type: "welcome", digest_window_seconds: 300)
    decision = described_class.decide(event: event)
    expect(decision).to be_digest
    expect(decision.digest_window_seconds).to eq(300)
    expect(decision.rule_id).to eq(rule.id)
  end

  it "returns dispatch with rule's priority when rule has no restrictions" do
    rule = NotificationRule.create!(notification_type: "welcome", priority: "critical")
    decision = described_class.decide(event: event)
    expect(decision).to be_dispatch
    expect(decision.priority).to eq("critical")
    expect(decision.rule_id).to eq(rule.id)
  end

  it "prioritizes disabled over rate limit (early return)" do
    NotificationRule.create!(notification_type: "welcome", channels: [], max_per_day: 1)
    3.times { create(:notification_audit, notification_type: "welcome", recipient_canonical: "a@b.com", status: "delivered") }
    decision = described_class.decide(event: event)
    expect(decision.reason).to eq("disabled")
  end
end
