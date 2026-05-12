# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::DlqRetrier do
  describe ".call (individual)" do
    it "resets job to pending with attempts=0" do
      job = create(:dispatch_queue, :failed)
      described_class.call(job, by: "ops@example.com")

      job.reload
      expect(job.status).to eq("pending")
      expect(job.attempts).to eq(0)
      expect(job.next_attempt_at).to be <= Time.current
    end

    it "creates dlq_retried audit with correct metadata" do
      job = create(:dispatch_queue, :failed)
      original_attempts = job.attempts
      described_class.call(job, by: "ops@example.com")

      audit = NotificationAudit.find_by!(notification_type: "_dlq_retried_")
      expect(audit.metadata["retried_by"]).to eq("ops@example.com")
      expect(audit.metadata["job_id"]).to eq(job.id)
      expect(audit.metadata["original_attempts"]).to eq(original_attempts)
    end

    it "rolls back if audit creation fails" do
      job = create(:dispatch_queue, :failed)
      allow(NotificationAudit).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect { described_class.call(job, by: "ops@example.com") }
        .to raise_error(ActiveRecord::RecordInvalid)

      expect(job.reload.status).to eq("failed")
    end
  end

  describe ".bulk_call" do
    it "retries up to cap jobs matching the reason" do
      3.times { create(:dispatch_queue, :failed, failed_reason: "Net::OpenTimeout: slow") }
      create(:dispatch_queue, :failed, failed_reason: "SendgridAdapter: 503")

      result = described_class.bulk_call(reason: "Net::OpenTimeout", by: "ops@example.com")
      expect(result[:retried]).to eq(3)

      pending_count = DispatchQueue.where(status: "pending").count
      expect(pending_count).to eq(3)
    end

    it "respects cap and reports total vs retried" do
      (Admin::DlqRetrier::CAP + 2).times do
        create(:dispatch_queue, :failed, failed_reason: "Net::OpenTimeout: slow")
      end

      result = described_class.bulk_call(reason: "Net::OpenTimeout", by: "ops@example.com")
      expect(result[:retried]).to eq(Admin::DlqRetrier::CAP)
      expect(result[:total]).to be > Admin::DlqRetrier::CAP
    end

    it "creates single bulk audit with count and reason_filter" do
      2.times { create(:dispatch_queue, :failed, failed_reason: "Net::OpenTimeout: x") }
      described_class.bulk_call(reason: "Net::OpenTimeout", by: "ops@example.com")

      audit = NotificationAudit.find_by!(notification_type: "_dlq_bulk_retried_")
      expect(audit.metadata["count"]).to eq(2)
      expect(audit.metadata["reason_filter"]).to eq("Net::OpenTimeout")
      expect(audit.metadata["retried_by"]).to eq("ops@example.com")
    end

    it "returns zeros when no matching jobs" do
      result = described_class.bulk_call(reason: "Nonexistent", by: "ops@example.com")
      expect(result[:retried]).to eq(0)
      expect(result[:total]).to eq(0)
    end
  end
end
