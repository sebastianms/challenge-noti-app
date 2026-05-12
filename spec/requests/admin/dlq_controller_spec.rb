# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::DlqController, type: :request do
  let(:admin)       { create(:admin_user, :admin) }
  let(:engineering) { create(:admin_user, :engineering) }
  let(:product)     { create(:admin_user, :product) }
  let!(:dead_job)   { create(:dispatch_queue, :failed, failed_reason: "Net::OpenTimeout: slow") }

  describe "authentication" do
    it "redirects unauthenticated request to login" do
      get admin_dlq_index_path
      expect(response).to redirect_to(new_admin_user_session_path)
    end
  end

  describe "authorization" do
    it "allows engineering to view DLQ" do
      sign_in engineering
      get admin_dlq_index_path
      expect(response).to have_http_status(:ok)
    end

    it "allows admin to view DLQ" do
      sign_in admin
      get admin_dlq_index_path
      expect(response).to have_http_status(:ok)
    end

    it "returns 403 for product" do
      sign_in product
      get admin_dlq_index_path
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "index" do
    before { sign_in admin }

    it "shows grouped jobs" do
      get admin_dlq_index_path
      expect(response.body).to include("Net")
    end
  end

  describe "retry (individual)" do
    before { sign_in admin }

    it "requeues job and redirects" do
      post retry_admin_dlq_path(dead_job)
      expect(response).to redirect_to(admin_dlq_index_path)
      expect(dead_job.reload.status).to eq("pending")
    end

    it "creates audit" do
      post retry_admin_dlq_path(dead_job)
      expect(NotificationAudit.find_by(notification_type: "_dlq_retried_")).to be_present
    end
  end

  describe "bulk_retry" do
    before { sign_in admin }

    it "retries matching jobs and redirects with notice" do
      post bulk_retry_admin_dlq_index_path, params: { reason: "Net::OpenTimeout" }
      expect(response).to redirect_to(admin_dlq_index_path)
      expect(dead_job.reload.status).to eq("pending")
    end

    it "redirects with alert when reason is blank" do
      post bulk_retry_admin_dlq_index_path, params: { reason: "" }
      expect(response).to redirect_to(admin_dlq_index_path)
    end
  end

  describe "discard" do
    before { sign_in admin }

    it "discards job with reason and redirects" do
      post discard_admin_dlq_path(dead_job), params: { reason: "recipient inválido" }
      expect(response).to redirect_to(admin_dlq_index_path)
      expect(dead_job.reload.status).to eq("discarded")
    end

    it "redirects with alert when reason is blank and job stays failed" do
      post discard_admin_dlq_path(dead_job), params: { reason: "" }
      expect(response).to have_http_status(:see_other)
      expect(dead_job.reload.status).to eq("failed")
    end

    it "creates dlq_discarded audit with correct by field" do
      post discard_admin_dlq_path(dead_job), params: { reason: "ticket closed" }
      audit = NotificationAudit.find_by!(notification_type: "_dlq_discarded_")
      expect(audit.metadata["discarded_by"]).to eq(admin.email)
    end
  end
end
