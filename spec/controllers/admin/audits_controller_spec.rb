# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::AuditsController, type: :request do
  let(:admin) { create(:admin_user, :admin) }

  before { sign_in admin }

  describe "GET /admin/audits" do
    it "redirects to login without session" do
      sign_out admin
      get "/admin/audits"
      expect(response).to redirect_to(new_admin_user_session_path)
    end

    it "returns 200 with valid session" do
      get "/admin/audits"
      expect(response).to have_http_status(:ok)
    end

    it "renders the filtered total" do
      create(:notification_audit, status: "failed")
      create(:notification_audit, status: "delivered")
      get "/admin/audits", params: { status: "failed" }
      expect(response.body).to include("Total: <strong>1</strong>")
    end

    it "paginates results" do
      55.times { create(:notification_audit, status: "failed") }
      get "/admin/audits", params: { status: "failed", page: 2, per_page: 50 }
      expect(response.body).to include("Página 2")
    end

    it "supports correlation_id lookup mode" do
      cid = SecureRandom.uuid
      create(:notification_audit, correlation_id: cid, status: "enqueued")
      create(:notification_audit, correlation_id: cid, status: "delivered")
      get "/admin/audits", params: { correlation_id: cid }
      expect(response.body).to include("Total: <strong>2</strong>")
    end

    it "renders metadata.reason for filtered rows" do
      create(:notification_audit, status: "filtered", metadata: { "reason" => "rate_limited", "rule_id" => 42 })
      get "/admin/audits"
      expect(response.body).to include("rate_limited")
      expect(response.body).to include("42")
    end

    it "renders an em-dash placeholder when metadata is nil" do
      create(:notification_audit, status: "enqueued", metadata: nil)
      get "/admin/audits"
      expect(response.body).to include("—")
    end
  end
end
