# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::TemplatesController, type: :request do
  let(:admin)       { create(:admin_user, :admin) }
  let(:product)     { create(:admin_user, :product) }
  let(:engineering) { create(:admin_user, :engineering) }
  let(:support)     { create(:admin_user, :support) }
  let!(:template)   { create(:notification_template) }

  before { Rails.cache.clear }

  describe "authentication" do
    it "redirects unauthenticated request to login" do
      get admin_templates_path
      expect(response).to redirect_to(new_admin_user_session_path)
    end
  end

  describe "authorization" do
    it "allows admin to list templates" do
      sign_in admin
      get admin_templates_path
      expect(response).to have_http_status(:ok)
    end

    it "allows product to list templates" do
      sign_in product
      get admin_templates_path
      expect(response).to have_http_status(:ok)
    end

    it "returns 403 for engineering" do
      sign_in engineering
      get admin_templates_path
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 403 for support" do
      sign_in support
      get admin_templates_path
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "CRUD" do
    before { sign_in admin }

    it "creates a new template and redirects" do
      post admin_templates_path, params: {
        notification_template: { notification_type: "mfa_alert", locale: "es",
                                 title: "Tu código: {{code}}", body: "Válido 10 min." }
      }
      expect(response).to redirect_to(admin_templates_path)
      expect(NotificationTemplate.find_by(notification_type: "mfa_alert")).to be_present
    end

    it "renders new form on validation error" do
      post admin_templates_path, params: {
        notification_template: { notification_type: "", locale: "es", title: "x", body: "y" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "updates an existing template" do
      patch admin_template_path(template), params: {
        notification_template: { notification_type: template.notification_type, locale: "es",
                                 title: "Nuevo título", body: template.body }
      }
      expect(response).to redirect_to(admin_templates_path)
      expect(template.reload.title).to eq("Nuevo título")
    end

    it "destroys a template" do
      delete admin_template_path(template)
      expect(response).to redirect_to(admin_templates_path)
      expect(NotificationTemplate.find_by(id: template.id)).to be_nil
    end
  end

  describe "preview" do
    before { sign_in admin }

    it "renders interpolated preview" do
      post preview_admin_template_path(template), params: {
        title: "Hola {{name}}", body: "Cuerpo {{name}}", context_json: '{"name":"Ana"}'
      }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Hola Ana")
    end

    it "shows warning for missing variable" do
      post preview_admin_template_path(template), params: {
        title: "Hola {{name}}, ID={{user_id}}", body: "x", context_json: '{"name":"Ana"}'
      }
      expect(response.body).to include("user_id")
    end

    it "handles invalid context_json gracefully" do
      post preview_admin_template_path(template), params: {
        title: "Hola {{name}}", body: "x", context_json: "not-json"
      }
      expect(response).to have_http_status(:ok)
    end
  end
end
