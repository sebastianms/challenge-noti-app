# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::MockData", type: :request do
  let(:admin_user) { create(:admin_user, :admin) }

  describe "POST /admin/mock_data with feature flag ON (default)" do
    before { sign_in admin_user }

    it "returns 303 redirect and generates data" do
      expect {
        post admin_mock_data_path
      }.to change(NotificationAudit, :count).by_at_least(40)
        .and change(DispatchQueue, :count).by_at_least(5)

      expect(response).to have_http_status(:found)
    end

    it "redirects to dashboard when no referer" do
      post admin_mock_data_path
      expect(response).to redirect_to(admin_dashboard_path)
    end
  end

  describe "POST /admin/mock_data with feature flag OFF" do
    before do
      sign_in admin_user
      allow(Admin::MockDataFeature).to receive(:enabled?).and_return(false)
    end

    it "returns 403" do
      post admin_mock_data_path
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /admin/mock_data as non-admin role" do
    before { sign_in create(:admin_user, :product) }

    it "returns 403 (role gate)" do
      post admin_mock_data_path
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "mock data button visibility" do
    context "as admin with flag ON" do
      before { sign_in admin_user }

      it "button is present on dashboard" do
        get admin_dashboard_path
        expect(response.body).to include("Generar data mock")
      end

      it "button is present on rules index" do
        get admin_rules_path
        expect(response.body).to include("Generar data mock")
      end
    end

    context "as product user" do
      before { sign_in create(:admin_user, :product) }

      it "button is absent on dashboard" do
        get admin_dashboard_path
        expect(response.body).not_to include("Generar data mock")
      end
    end

    context "with flag OFF" do
      before do
        sign_in admin_user
        allow(Admin::MockDataFeature).to receive(:enabled?).and_return(false)
      end

      it "button is absent on dashboard" do
        get admin_dashboard_path
        expect(response.body).not_to include("Generar data mock")
      end
    end
  end

  describe "unauthenticated" do
    it "redirects to login" do
      post admin_mock_data_path
      expect(response).to redirect_to(new_admin_user_session_path)
    end
  end
end
