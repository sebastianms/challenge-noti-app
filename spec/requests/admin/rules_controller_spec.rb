# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Rules", type: :request do
  let(:product_user) { create(:admin_user, :product) }

  before { sign_in product_user }

  describe "GET /admin/rules" do
    it "returns 200 and lists rules" do
      rule = create(:notification_rule)
      get admin_rules_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(rule.notification_type)
    end
  end

  describe "GET /admin/rules/new" do
    it "returns 200" do
      get new_admin_rule_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /admin/rules" do
    let(:valid_params) do
      { notification_rule: { notification_type: "invoice", enabled: true, priority: "standard",
                              max_per_day: 5, cooldown_seconds: nil, digest_window_seconds: nil,
                              channels: [ "email" ] } }
    end

    context "with valid params" do
      it "creates a rule and records a RuleChange" do
        expect {
          post admin_rules_path, params: valid_params
        }.to change(NotificationRule, :count).by(1)
          .and change(RuleChange, :count).by(1)

        expect(RuleChange.last).to have_attributes(action: "created", before: nil)
      end

      it "redirects to index" do
        post admin_rules_path, params: valid_params
        expect(response).to redirect_to(admin_rules_path)
      end
    end

    context "with invalid params" do
      it "re-renders new with 422" do
        post admin_rules_path, params: { notification_rule: { notification_type: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /admin/rules/:id/edit" do
    it "returns 200" do
      rule = create(:notification_rule)
      get edit_admin_rule_path(rule)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /admin/rules/:id" do
    let(:rule) { create(:notification_rule, max_per_day: 1) }

    context "with valid params" do
      it "updates the rule and records a RuleChange with before/after" do
        patch admin_rule_path(rule), params: {
          notification_rule: { notification_type: rule.notification_type, max_per_day: 10, enabled: true }
        }
        expect(rule.reload.max_per_day).to eq(10)

        change = RuleChange.last
        expect(change.action).to eq("updated")
        expect(change.before["max_per_day"]).to eq(1)
        expect(change.after["max_per_day"]).to eq(10)
      end

      it "invalidates cache for that notification_type" do
        rule_type = rule.notification_type  # force creation before mock
        allow(RuleCache).to receive(:invalidate)
        patch admin_rule_path(rule), params: {
          notification_rule: { notification_type: rule_type, max_per_day: 2, enabled: true }
        }
        expect(RuleCache).to have_received(:invalidate).with(rule_type).at_least(:once)
      end

      it "redirects to index" do
        patch admin_rule_path(rule), params: {
          notification_rule: { notification_type: rule.notification_type, enabled: true }
        }
        expect(response).to redirect_to(admin_rules_path)
      end
    end

    context "with invalid params" do
      it "re-renders edit with 422" do
        patch admin_rule_path(rule), params: {
          notification_rule: { notification_type: rule.notification_type, priority: "invalid_priority" }
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /admin/rules/:id" do
    it "destroys the rule and records a deleted RuleChange" do
      rule = create(:notification_rule)
      expect {
        delete admin_rule_path(rule)
      }.to change(NotificationRule, :count).by(-1)
        .and change(RuleChange, :count).by(1)

      change = RuleChange.last
      expect(change.action).to eq("deleted")
      expect(change.after).to be_nil
      expect(change.before["notification_type"]).to eq(rule.notification_type)
    end

    it "redirects to index" do
      rule = create(:notification_rule)
      delete admin_rule_path(rule)
      expect(response).to redirect_to(admin_rules_path)
    end
  end

  describe "GET /admin/rules/:id/history" do
    it "lists changes for the rule" do
      rule   = create(:notification_rule)
      change = create(:rule_change, :updated, notification_rule: rule, admin_user: product_user)
      get history_admin_rule_path(rule)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(change.action.upcase)
    end
  end
end
