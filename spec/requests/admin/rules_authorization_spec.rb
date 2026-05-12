# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Rules authorization", type: :request do
  shared_examples "allows access to rules" do |role|
    let(:user) { create(:admin_user, role) }
    before { sign_in user }

    it "GET index returns 200" do
      get admin_rules_path
      expect(response).to have_http_status(:ok)
    end

    it "GET new returns 200" do
      get new_admin_rule_path
      expect(response).to have_http_status(:ok)
    end
  end

  shared_examples "denies access to rules" do |role|
    let(:user) { create(:admin_user, role) }
    before { sign_in user }

    it "GET index returns 403" do
      get admin_rules_path
      expect(response).to have_http_status(:forbidden)
    end

    it "GET new returns 403" do
      get new_admin_rule_path
      expect(response).to have_http_status(:forbidden)
    end

    it "POST create returns 403" do
      post admin_rules_path, params: {
        notification_rule: { notification_type: "test", enabled: true }
      }
      expect(response).to have_http_status(:forbidden)
    end

    it "DELETE destroy returns 403" do
      rule = create(:notification_rule)
      delete admin_rule_path(rule)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "admin role"   do include_examples "allows access to rules", :admin   end
  describe "product role" do include_examples "allows access to rules", :product end

  describe "support role"     do include_examples "denies access to rules", :support     end
  describe "engineering role" do include_examples "denies access to rules", :engineering end
end
