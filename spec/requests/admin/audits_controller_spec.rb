# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::AuditsController", type: :request do
  let(:admin) { create(:admin_user, :admin) }

  before { sign_in admin }

  describe "GET /admin/audits" do
    it "returns 200 for authenticated admin" do
      get admin_audits_path
      expect(response).to have_http_status(:ok)
    end

    it "redirects to login when unauthenticated" do
      sign_out admin
      get admin_audits_path
      expect(response).to redirect_to(new_admin_user_session_path)
    end

    context "with reason filter" do
      it "returns only audits matching the reason" do
        create(:notification_audit, :filtered, notification_type: "birthday")
        create(:notification_audit, status: "delivered", notification_type: "invoice", metadata: nil)

        get admin_audits_path, params: { reason: "rate_limited" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("birthday")
        expect(response.body).not_to include("invoice")
      end
    end

    context "with rule_id filter" do
      it "returns only audits matching rule_id" do
        create(:notification_audit, :filtered, notification_type: "promo")

        get admin_audits_path, params: { rule_id: "1" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("promo")
      end
    end

    context "CSV format" do
      it "returns text/csv with audit data" do
        create(:notification_audit, :filtered, notification_type: "birthday",
               recipient_canonical: "csv@example.com")

        get admin_audits_path(format: :csv)

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("text/csv")
        expect(response.body).to include("correlation_id")
        expect(response.body).to include("csv@example.com")
      end

      it "returns only header row when no audits match" do
        get admin_audits_path(format: :csv, params: { recipient: "nobody@example.com" })

        expect(response.body.lines.size).to eq(1)
        expect(response.body).to include("correlation_id")
      end
    end
  end

  describe "GET /admin/audits/:correlation_id" do
    let(:corr_id) { SecureRandom.uuid }

    before do
      create(:notification_audit, correlation_id: corr_id, status: "enqueued",
             notification_type: "birthday", recipient_canonical: "juan@example.com")
      create(:notification_audit, correlation_id: corr_id, status: "delivered",
             notification_type: "birthday", recipient_canonical: "juan@example.com")
    end

    it "returns 200 and shows the timeline" do
      get admin_audit_path(corr_id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("enqueued")
      expect(response.body).to include("delivered")
    end

    it "shows rule link when rule_id present in metadata" do
      rule = create(:notification_rule, notification_type: "timeline_test")
      cid  = SecureRandom.uuid
      create(:notification_audit, :filtered, correlation_id: cid,
             notification_type: "timeline_test",
             metadata: { "reason" => "rate_limited", "rule_id" => rule.id })

      get admin_audit_path(cid)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("timeline_test")
    end
  end
end
