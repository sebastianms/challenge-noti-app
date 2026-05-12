# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rule change recording", type: :request do
  let(:admin_user) { create(:admin_user, :admin) }

  before { sign_in admin_user }

  describe "create action" do
    it "persists 1 RuleChange row with action=created and correct after" do
      expect {
        post admin_rules_path, params: {
          notification_rule: { notification_type: "welcome", enabled: true,
                               priority: "standard", channels: [ "email" ] }
        }
      }.to change(RuleChange, :count).by(1)

      rc = RuleChange.last
      expect(rc.action).to eq("created")
      expect(rc.before).to be_nil
      expect(rc.after["notification_type"]).to eq("welcome")
      expect(rc.admin_user_id).to eq(admin_user.id)
    end
  end

  describe "update action" do
    it "persists 1 RuleChange row with correct before/after diff" do
      rule = create(:notification_rule, :with_rate_limit, max_per_day: 3)

      expect {
        patch admin_rule_path(rule), params: {
          notification_rule: { notification_type: rule.notification_type,
                               enabled: rule.enabled, max_per_day: 7 }
        }
      }.to change(RuleChange, :count).by(1)

      rc = RuleChange.last
      expect(rc.action).to eq("updated")
      expect(rc.before["max_per_day"]).to eq(3)
      expect(rc.after["max_per_day"]).to eq(7)
      expect(rc.admin_user_id).to eq(admin_user.id)
    end
  end

  describe "destroy action" do
    it "persists 1 RuleChange row with action=deleted and correct before" do
      rule = create(:notification_rule)
      type = rule.notification_type

      expect {
        delete admin_rule_path(rule)
      }.to change(RuleChange, :count).by(1)

      rc = RuleChange.last
      expect(rc.action).to eq("deleted")
      expect(rc.after).to be_nil
      expect(rc.before["notification_type"]).to eq(type)
      expect(rc.notification_rule_id).to be_nil
      expect(rc.admin_user_id).to eq(admin_user.id)
    end
  end
end
