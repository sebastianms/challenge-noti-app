# frozen_string_literal: true

require "rails_helper"

RSpec.describe RuleChange, type: :model do
  describe "action invariants" do
    it "created allows nil before and requires after" do
      rc = build(:rule_change, :created)
      expect(rc).to be_valid
    end

    it "created rejects non-nil before" do
      rc = build(:rule_change, :created, before: { "x" => 1 })
      expect(rc).not_to be_valid
      expect(rc.errors[:before]).to be_present
    end

    it "updated requires both before and after" do
      rc = build(:rule_change, :updated)
      expect(rc).to be_valid
    end

    it "updated rejects nil before" do
      rc = build(:rule_change, :updated, before: nil)
      expect(rc).not_to be_valid
    end

    it "updated rejects nil after" do
      rc = build(:rule_change, :updated, after: nil)
      expect(rc).not_to be_valid
    end

    it "deleted requires before and rejects after" do
      rc = build(:rule_change, :deleted)
      expect(rc).to be_valid
    end

    it "deleted rejects non-nil after" do
      rc = build(:rule_change, :deleted, after: { "x" => 1 })
      expect(rc).not_to be_valid
      expect(rc.errors[:after]).to be_present
    end
  end

  it "rejects unknown action" do
    rc = build(:rule_change, action: "renamed", before: nil, after: { "x" => 1 })
    expect(rc).not_to be_valid
  end

  it "notification_rule can be nil (preserved after deletion)" do
    rc = build(:rule_change, :deleted)
    expect(rc).to be_valid
  end
end
