# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin role gates", type: :request do
  let(:admin)       { create(:admin_user, :admin) }
  let(:product)     { create(:admin_user, :product) }
  let(:engineering) { create(:admin_user, :engineering) }
  let(:support)     { create(:admin_user, :support) }

  def request_for(section)
    case section
    when :dashboard then get admin_dashboard_path
    when :rules     then get admin_rules_path
    when :mock_data then post admin_mock_data_path
    end
  end

  shared_examples "allows access to" do |section|
    it "returns non-403 for #{section}" do
      request_for(section)
      expect(response).not_to have_http_status(:forbidden)
    end
  end

  shared_examples "denies access to" do |section|
    it "returns 403 for #{section}" do
      request_for(section)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "admin role" do
    before { sign_in admin }

    include_examples "allows access to", :dashboard
    include_examples "allows access to", :rules
    include_examples "allows access to", :mock_data
  end

  describe "product role" do
    before { sign_in product }

    include_examples "allows access to", :dashboard
    include_examples "allows access to", :rules
    include_examples "denies access to", :mock_data
  end

  describe "engineering role" do
    before { sign_in engineering }

    include_examples "allows access to", :dashboard
    include_examples "denies access to", :rules
    include_examples "denies access to", :mock_data
  end

  describe "support role" do
    before { sign_in support }

    include_examples "allows access to", :dashboard
    include_examples "denies access to", :rules
    include_examples "denies access to", :mock_data
  end

  describe "unauthenticated user" do
    it "redirects to login when accessing dashboard" do
      get admin_dashboard_path
      expect(response).to redirect_to(new_admin_user_session_path)
    end
  end
end
