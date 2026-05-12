# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::DlqDiscarder do
  describe ".call" do
    it "marks job as discarded" do
      job = create(:dispatch_queue, :failed)
      described_class.call(job, reason: "recipient inválido", by: "ops@example.com")
      expect(job.reload.status).to eq("discarded")
    end

    it "creates dlq_discarded audit with metadata" do
      job = create(:dispatch_queue, :failed)
      described_class.call(job, reason: "ticket cerrado", by: "ops@example.com")

      audit = NotificationAudit.find_by!(notification_type: "_dlq_discarded_")
      expect(audit.metadata["discarded_by"]).to eq("ops@example.com")
      expect(audit.metadata["reason"]).to eq("ticket cerrado")
      expect(audit.metadata["job_id"]).to eq(job.id)
    end

    it "raises ArgumentError when reason is blank" do
      job = create(:dispatch_queue, :failed)
      expect { described_class.call(job, reason: "", by: "ops@example.com") }
        .to raise_error(ArgumentError, /reason is required/)
    end

    it "rolls back if audit creation fails" do
      job = create(:dispatch_queue, :failed)
      allow(NotificationAudit).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect { described_class.call(job, reason: "test", by: "ops@example.com") }
        .to raise_error(ActiveRecord::RecordInvalid)

      expect(job.reload.status).to eq("failed")
    end
  end
end
