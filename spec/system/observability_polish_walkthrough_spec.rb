# frozen_string_literal: true

require "rails_helper"

# Walkthrough de integración para el bloque Polish de 009-observability-perf-hardening.
# Cubre los escenarios automatizables de quickstart.md (E4, E7, E8-ext, E9).
# Los escenarios E1/E3/E5/E6 requieren infraestructura externa o acciones manuales
# y están documentados en quickstart.md como validación manual.
RSpec.describe "Observability polish walkthrough", type: :request do
  # ── E4 — Endpoint /metrics ────────────────────────────────────────────────
  describe "E4 — /metrics endpoint (US1)" do
    let(:user) { ENV.fetch("METRICS_BASIC_AUTH_USER", "metrics") }
    let(:pass) { ENV.fetch("METRICS_BASIC_AUTH_PASSWORD", "secret") }

    before do
      stub_const("MetricsAuth::USER", user)
      stub_const("MetricsAuth::PASSWORD", pass)
      stub_const("MetricsAuth::CREDENTIALS_PRESENT", true)
    end

    it "returns 401 without credentials (E4-a)" do
      get metrics_path
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 200 with valid credentials (E4-b)" do
      get metrics_path, headers: { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(user, pass) }
      expect(response).to have_http_status(:ok)
    end

    it "response body contains all required metric names (E4-c)" do
      get metrics_path, headers: { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(user, pass) }
      %w[
        notif_queue_depth
        notif_dlq_size
        notif_events_ingested_total
        notif_dispatch_errors_total
        notif_bounce_rate_5m
        notif_webhook_lag_seconds
      ].each do |metric|
        expect(response.body).to include(metric), "Metric #{metric} missing from response"
      end
    end

    it "includes Cache-Control header (E4-d)" do
      get metrics_path, headers: { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(user, pass) }
      expect(response.headers["Cache-Control"]).to include("max-age=5")
    end
  end

  # ── E7 — Home page pública ────────────────────────────────────────────────
  describe "E7 — Home page sin sesión (US5)" do
    before { get root_path }

    it "returns 200 without session (E7-a)" do
      expect(response).to have_http_status(:ok)
    end

    it "does not redirect (E7-b)" do
      expect(response).not_to be_redirect
    end

    it "describes the 4-step flow (E7-c)" do
      %w[Ingesta Decisión Despacho Auditoría].each do |step|
        expect(response.body).to include(step)
      end
    end

    it "renders runbook and tour links (E7-d)" do
      expect(response.body).to include("runbook.md")
      expect(response.body).to include("app-tour.md")
    end

    it "renders the public endpoints table (E7-e)" do
      expect(response.body).to include("/metrics")
      expect(response.body).to include("/internal/ingest")
      expect(response.body).to include("/webhooks/sendgrid")
    end
  end

  # ── E8-ext — Sidebar con sección Recursos ────────────────────────────────
  describe "E8-ext — Sidebar recursos (extensión US6)" do
    let(:admin) { create(:admin_user, :admin) }

    before { sign_in admin }

    it "renders runbook and tour links in the sidebar on every admin page" do
      [ admin_dashboard_path, admin_audits_path, admin_rules_path, admin_dlq_index_path ].each do |path|
        get path
        expect(response.body).to include("runbook.md"), "Runbook missing on #{path}"
        expect(response.body).to include("app-tour.md"), "Tour missing on #{path}"
      end
    end

    it "renders Noti Central as a link to the dashboard" do
      get admin_audits_path
      expect(response.body).to include(admin_dashboard_path)
    end
  end

  # ── E9 — DLQ walkthrough: generar datos y reintentar ─────────────────────
  describe "E9 — DLQ saturada: datos mock y bulk retry (US runbook)" do
    let(:admin) { create(:admin_user, :admin) }

    before { sign_in admin }

    context "con jobs en DLQ" do
      let!(:jobs) do
        3.times.map do |i|
          create(:dispatch_queue, :failed,
                 failed_reason: "Net::OpenTimeout: timeout ##{i}",
                 attempts: DispatchQueue::MAX_ATTEMPTS)
        end
      end

      it "DLQ index lists failed jobs grouped by reason (E9-a)" do
        get admin_dlq_index_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Net::OpenTimeout")
      end

      it "bulk retry re-enqueues jobs matching the reason filter (E9-b)" do
        expect {
          post bulk_retry_admin_dlq_index_path, params: { reason: "Net::OpenTimeout" }
        }.to change { DispatchQueue.where(status: "pending").count }.by(3)
      end

      it "single retry re-enqueues a specific job (E9-c)" do
        job = jobs.first
        expect {
          post retry_admin_dlq_path(job)
        }.to change { job.reload.status }.from("failed").to("pending")
      end
    end
  end
end
