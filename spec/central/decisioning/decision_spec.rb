# frozen_string_literal: true

require "rails_helper"

RSpec.describe Decision do
  describe ".dispatch" do
    it "creates a dispatch decision with optional rule_id and priority" do
      d = described_class.dispatch(rule_id: 42, priority: "critical")
      expect(d).to be_dispatch
      expect(d.rule_id).to eq(42)
      expect(d.priority).to eq("critical")
    end

    it "allows no rule_id (default fallback)" do
      d = described_class.dispatch
      expect(d).to be_dispatch
      expect(d.rule_id).to be_nil
    end
  end

  describe ".digest" do
    it "creates a digest decision with rule_id and window" do
      d = described_class.digest(rule_id: 7, window: 300)
      expect(d).to be_digest
      expect(d.rule_id).to eq(7)
      expect(d.digest_window_seconds).to eq(300)
    end
  end

  describe ".filter" do
    it "creates a filter decision with reason and rule_id" do
      d = described_class.filter(reason: "rate_limited", rule_id: 9)
      expect(d).to be_filter
      expect(d.reason).to eq("rate_limited")
      expect(d.rule_id).to eq(9)
    end
  end

  describe "predicates" do
    it "is mutually exclusive (only one of dispatch?/digest?/filter? is true)" do
      d = described_class.filter(reason: "disabled", rule_id: 1)
      expect([ d.dispatch?, d.digest?, d.filter? ].count(true)).to eq(1)
    end
  end
end
