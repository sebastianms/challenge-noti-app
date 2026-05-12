# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Dashboard", type: :request do
  before { Rails.cache.clear }

  shared_examples "renders dashboard for" do |role|
    let(:user) { create(:admin_user, role) }

    before { sign_in user }

    it "returns 200" do
      get admin_dashboard_path
      expect(response).to have_http_status(:ok)
    end

    it "includes all 4 dashboard sections" do
      get admin_dashboard_path
      expect(response.body).to include('data-section="counters"')
      expect(response.body).to include('data-section="volume"')
      expect(response.body).to include('data-section="filter-rate"')
      expect(response.body).to include('data-section="error-rate"')
    end
  end

  describe "admin role"       do include_examples "renders dashboard for", :admin       end
  describe "product role"     do include_examples "renders dashboard for", :product     end
  describe "engineering role" do include_examples "renders dashboard for", :engineering end
  describe "support role"     do include_examples "renders dashboard for", :support     end

  describe "unauthenticated" do
    it "redirects to login" do
      get admin_dashboard_path
      expect(response).to redirect_to(new_admin_user_session_path)
    end
  end
end
