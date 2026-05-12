# frozen_string_literal: true

require "rails_helper"

# Walkthrough end-to-end del panel admin: US1 → US2 → US3 → US4.
# Un solo admin logueado recorre las 4 user stories en secuencia.
RSpec.describe "Admin UI walkthrough", type: :request do
  let(:admin) { create(:admin_user, :admin) }

  before { sign_in admin }

  describe "US1 — auth gate" do
    it "unauthenticated request redirects to login" do
      sign_out admin
      get admin_dashboard_path
      expect(response).to redirect_to(new_admin_user_session_path)
    end

    it "authenticated admin accesses dashboard" do
      get admin_dashboard_path
      expect(response).to have_http_status(:ok)
    end

    it "support role is denied access to rules" do
      support = create(:admin_user, :support)
      sign_in support
      get admin_rules_path
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "US2 — dashboard renders all KPI sections" do
    it "shows all 4 sections" do
      get admin_dashboard_path
      %w[counters volume filter-rate error-rate].each do |section|
        expect(response.body).to include("data-section=\"#{section}\"")
      end
    end
  end

  describe "US3 — CRUD rules + history" do
    it "creates, updates and shows history for a rule" do
      # Create
      post admin_rules_path, params: {
        notification_rule: { notification_type: "demo_phase7", enabled: true,
                             priority: "standard", max_per_day: 2, channels: [ "email" ] }
      }
      expect(response).to redirect_to(admin_rules_path)
      rule = NotificationRule.find_by!(notification_type: "demo_phase7")

      # Verify it appears in index
      get admin_rules_path
      expect(response.body).to include("demo_phase7")

      # Update
      patch admin_rule_path(rule), params: {
        notification_rule: { notification_type: "demo_phase7", enabled: true, max_per_day: 5 }
      }
      expect(response).to redirect_to(admin_rules_path)
      expect(rule.reload.max_per_day).to eq(5)

      # History shows 2 entries
      get history_admin_rule_path(rule)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("CREATED")
      expect(response.body).to include("UPDATED")

      # RuleChange records are correct
      changes = RuleChange.where(notification_rule: rule).order(:changed_at)
      expect(changes.map(&:action)).to eq(%w[created updated])
      expect(changes.last.before["max_per_day"]).to eq(2)
      expect(changes.last.after["max_per_day"]).to eq(5)
    end

    it "destroys a rule and records deleted RuleChange" do
      rule = create(:notification_rule)
      delete admin_rule_path(rule)
      expect(response).to redirect_to(admin_rules_path)
      expect(NotificationRule.exists?(rule.id)).to be false
      expect(RuleChange.last.action).to eq("deleted")
    end
  end

  describe "US4 — mock data" do
    it "generates data and redirects with flash" do
      post admin_mock_data_path
      expect(response).to redirect_to(admin_dashboard_path)
      expect(NotificationRule.count).to be >= 5
      expect(NotificationAudit.count).to be >= 20
    end

    it "non-admin role is denied mock_data" do
      product = create(:admin_user, :product)
      sign_in product
      post admin_mock_data_path
      expect(response).to have_http_status(:forbidden)
    end

    it "flag off returns 403" do
      allow(Admin::MockDataFeature).to receive(:enabled?).and_return(false)
      post admin_mock_data_path
      expect(response).to have_http_status(:forbidden)
    end
  end
end
