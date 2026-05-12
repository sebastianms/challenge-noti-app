# frozen_string_literal: true

require "rails_helper"

# Walkthrough end-to-end Phase 9: US1 → US2 con admin logueado.
RSpec.describe "Admin UI Templates + DLQ walkthrough", type: :request do
  let(:admin)       { create(:admin_user, :admin) }
  let(:engineering) { create(:admin_user, :engineering) }

  before do
    Rails.cache.clear
    sign_in admin
  end

  describe "US1 — Editor de templates" do
    describe "E1: override visible en payload del evento" do
      it "uses DB override subject/body when sending notification" do
        post admin_templates_path, params: {
          notification_template: {
            notification_type: "birthday",
            locale:            "es",
            title:             "Hoy es tu día {{name}} 🎉",
            body:              "Te deseamos lo mejor."
          }
        }
        expect(response).to redirect_to(admin_templates_path)

        result = BirthdayNotification.send("juan@example.com", context: { name: "Juan" })
        event  = NotificationEvent.find_by!(correlation_id: result.correlation_id)
        expect(event.payload["subject"]).to eq("Hoy es tu día Juan 🎉")
        expect(event.payload["body"]).to eq("Te deseamos lo mejor.")
      end
    end

    describe "E2: preview con variable faltante" do
      it "shows warning for unresolved variable" do
        tmpl = create(:notification_template)
        post preview_admin_template_path(tmpl), params: {
          title:        "Hola {{name}}, ID={{user_id}}",
          body:         "x",
          context_json: '{"name":"Ana"}'
        }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("user_id")
        expect(response.body).to include("Hola Ana, ID=")
      end
    end

    describe "E6: gating — engineering no puede editar templates" do
      it "returns 403 for engineering on templates index" do
        sign_in engineering
        get admin_templates_path
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "E7: fallback sin override" do
      it "uses Ruby class methods when no template override exists" do
        result = BirthdayNotification.send("ana@example.com", context: { name: "Ana" })
        event  = NotificationEvent.find_by!(correlation_id: result.correlation_id)
        expect(event.payload["subject"]).to eq("¡Feliz cumpleaños, Ana!")
      end
    end
  end

  describe "US2 — Gestión de la DLQ" do
    let!(:dead_job) do
      create(:dispatch_queue, :failed, failed_reason: "Net::OpenTimeout: execution expired")
    end

    describe "E3: reintento individual" do
      it "requeues job and creates audit" do
        post retry_admin_dlq_path(dead_job)
        expect(response).to redirect_to(admin_dlq_index_path)

        dead_job.reload
        expect(dead_job.status).to eq("pending")
        expect(dead_job.attempts).to eq(0)

        audit = NotificationAudit.find_by!(notification_type: "_dlq_retried_")
        expect(audit.metadata["retried_by"]).to eq(admin.email)
        expect(audit.metadata["job_id"]).to eq(dead_job.id)
      end
    end

    describe "E4: reintento masivo capeado" do
      it "retries up to 500 jobs and reports remainder" do
        4.times { create(:dispatch_queue, :failed, failed_reason: "Net::OpenTimeout: slow") }

        post bulk_retry_admin_dlq_index_path, params: { reason: "Net::OpenTimeout" }
        expect(response).to redirect_to(admin_dlq_index_path)

        retried = DispatchQueue.where(status: "pending").count
        expect(retried).to eq(5)

        audit = NotificationAudit.find_by!(notification_type: "_dlq_bulk_retried_")
        expect(audit.metadata["count"]).to eq(5)
        expect(audit.metadata["reason_filter"]).to eq("Net::OpenTimeout")
      end
    end

    describe "E5: descarte con motivo" do
      it "discards job and creates audit trail" do
        post discard_admin_dlq_path(dead_job), params: { reason: "recipient inválido confirmado" }
        expect(response).to redirect_to(admin_dlq_index_path)

        dead_job.reload
        expect(dead_job.status).to eq("discarded")

        audit = NotificationAudit.find_by!(notification_type: "_dlq_discarded_")
        expect(audit.metadata["discarded_by"]).to eq(admin.email)
        expect(audit.metadata["reason"]).to eq("recipient inválido confirmado")
      end
    end

    describe "E6: gating — product no puede acceder a DLQ" do
      it "returns 403 for product on DLQ index" do
        sign_in create(:admin_user, :product)
        get admin_dlq_index_path
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "unauthenticated" do
      it "redirects to login" do
        sign_out admin
        get admin_dlq_index_path
        expect(response).to redirect_to(new_admin_user_session_path)
      end
    end
  end
end
