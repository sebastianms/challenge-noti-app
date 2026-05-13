# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::RolloutFlags", type: :request do
  let(:admin) { create(:admin_user, :admin) }

  before { sign_in admin }

  describe "GET /admin/rollout_flags" do
    it "returns 200" do
      get admin_rollout_flags_path
      expect(response).to have_http_status(:ok)
    end

    it "lists existing flags" do
      create(:notification_rollout_flag, notification_type: "promo_weekend", team_name: "Crecimiento")
      get admin_rollout_flags_path
      expect(response.body).to include("promo_weekend")
    end
  end

  describe "GET /admin/rollout_flags/new" do
    it "returns 200" do
      get new_admin_rollout_flag_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /admin/rollout_flags" do
    it "creates a flag and redirects" do
      expect {
        post admin_rollout_flags_path, params: {
          notification_rollout_flag: { notification_type: "invoice_ready", team_name: "Finanzas", enrolled: true }
        }
      }.to change(NotificationRolloutFlag, :count).by(1)
      expect(response).to redirect_to(admin_rollout_flags_path)
    end

    it "renders new on invalid params" do
      post admin_rollout_flags_path, params: {
        notification_rollout_flag: { notification_type: "", team_name: "Equipo" }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /admin/rollout_flags/:id" do
    let!(:flag) { create(:notification_rollout_flag, enrolled: true) }

    it "updates enrolled and redirects" do
      patch admin_rollout_flag_path(flag), params: {
        notification_rollout_flag: { enrolled: false }
      }
      expect(flag.reload.enrolled).to be false
      expect(response).to redirect_to(admin_rollout_flags_path)
    end
  end

  describe "DELETE /admin/rollout_flags/:id" do
    let!(:flag) { create(:notification_rollout_flag) }

    it "destroys the flag" do
      expect {
        delete admin_rollout_flag_path(flag)
      }.to change(NotificationRolloutFlag, :count).by(-1)
    end
  end

  describe "access control" do
    %w[product engineering support].each do |role|
      it "returns 403 for #{role} role" do
        sign_in create(:admin_user, role: role)
        get admin_rollout_flags_path
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
