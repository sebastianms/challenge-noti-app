# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Sessions", type: :request do
  let(:admin) { create(:admin_user, :admin) }
  let(:valid_password) { "Admin12345678!" }

  def login(email:, password:)
    post admin_user_session_path,
         params: { admin_user: { email:, password: } }
  end

  describe "GET /admin/login" do
    it "renders login form" do
      get new_admin_user_session_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ingresar")
    end
  end

  describe "POST /admin/login" do
    context "with valid credentials" do
      it "redirects to dashboard" do
        login(email: admin.email, password: valid_password)
        expect(response).to redirect_to(admin_dashboard_path)
      end
    end

    context "with invalid credentials" do
      it "renders login form with generic message (paranoid)" do
        login(email: admin.email, password: "wrong_password_123")
        expect(response).to have_http_status(:unprocessable_entity)
        # Devise paranoid emits a single generic message
        expect(response.body).to match(/invalid/i)
      end
    end

    context "after 5 failed attempts (lockable)" do
      it "locks the account" do
        5.times { login(email: admin.email, password: "bad_password_123") }
        admin.reload
        expect(admin.access_locked?).to be(true)
      end

      it "returns unprocessable_entity on 6th attempt" do
        6.times { login(email: admin.email, password: "bad_password_123") }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /admin/logout" do
    it "invalidates the session and redirects to login" do
      sign_in admin
      delete destroy_admin_user_session_path
      expect(response).to redirect_to(new_admin_user_session_path)
    end

    it "does not allow accessing protected routes after logout" do
      sign_in admin
      delete destroy_admin_user_session_path
      get admin_dashboard_path
      expect(response).to redirect_to(new_admin_user_session_path)
    end
  end
end
