# frozen_string_literal: true

require "rails_helper"

# Walkthrough end-to-end del panel admin Phase 8: US3 → US1 → US2.
# Un solo admin logueado recorre las 3 user stories en secuencia.
RSpec.describe "Admin UI Auditoría + Blacklist walkthrough", type: :request do
  let(:admin) { create(:admin_user, :admin) }

  before { sign_in admin }

  describe "US3 — migración a Devise" do
    it "unauthenticated request redirects to login" do
      sign_out admin
      get admin_audits_path
      expect(response).to redirect_to(new_admin_user_session_path)
    end

    it "unauthenticated blacklist request redirects to login" do
      sign_out admin
      get admin_blacklist_index_path
      expect(response).to redirect_to(new_admin_user_session_path)
    end

    it "engineering can read audits but cannot write blacklist" do
      engineering = create(:admin_user, :engineering)
      sign_in engineering

      get admin_audits_path
      expect(response).to have_http_status(:ok)

      post admin_blacklist_index_path, params: { recipient: "x@example.com", scope: "global" }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "US1 — soporte busca por qué Juan no recibió un envío" do
    let(:cid) { SecureRandom.uuid }

    before do
      create(:notification_audit, correlation_id: cid, status: "enqueued",
             notification_type: "birthday", recipient_canonical: "juan@example.com")
      create(:notification_audit, correlation_id: cid, status: "filtered",
             notification_type: "birthday", recipient_canonical: "juan@example.com",
             metadata: { "reason" => "rate_limited", "rule_id" => nil })
    end

    it "finds the event by recipient filter and opens timeline" do
      get admin_audits_path, params: { recipient: "juan@example.com" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("juan@example.com")

      get admin_audit_path(cid)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("enqueued")
      expect(response.body).to include("filtered")
      expect(response.body).to include("rate_limited")
    end

    it "filters by reason=rate_limited returns the event" do
      get admin_audits_path, params: { reason: "rate_limited" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("birthday")
    end

    it "CSV export returns the event" do
      get admin_audits_path(format: :csv), params: { recipient: "juan@example.com" }
      expect(response.content_type).to include("text/csv")
      expect(response.body).to include("juan@example.com")
    end
  end

  describe "US2 — compliance gestiona blacklist con audit trail y CSV" do
    it "creates, lists and deletes a blacklist entry with correct removed_by" do
      # Alta manual
      post admin_blacklist_index_path, params: {
        recipient: "blocked@example.com", scope: "global", reason: "GDPR ticket #99"
      }
      expect(response).to redirect_to(admin_blacklist_index_path)

      # Aparece en el index
      get admin_blacklist_index_path
      expect(response.body).to include("blocked@example.com")

      # Export CSV
      get admin_blacklist_index_path(format: :csv)
      expect(response.content_type).to include("text/csv")
      expect(response.body).to include("blocked@example.com")

      # Baja auditada con email del admin
      entry = NotificationBlacklist.find_by!(recipient_canonical: "blocked@example.com")
      delete admin_blacklist_path(entry), params: { reason: "ticket closed" }
      expect(response).to redirect_to(admin_blacklist_index_path)

      audit = NotificationAudit.find_by!(notification_type: "_blacklist_removed_")
      expect(audit.metadata["removed_by"]).to eq(admin.email)
      expect(audit.metadata["reason"]).to eq("ticket closed")
    end
  end
end
