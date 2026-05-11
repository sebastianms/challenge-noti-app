# frozen_string_literal: true

require "rails_helper"

RSpec.describe Worker, type: :model do
  # notification_events has a composite PK (id, idempotency_window_ts).
  # event.id returns the composite array; event.attributes["id"] gives the raw integer.
  let!(:event)    { create(:notification_event) }
  let(:event_rid) { event.attributes["id"] }
  let!(:job)      { create(:dispatch_queue, event_id: event_rid) }

  before do
    stub_request(:post, "https://api.sendgrid.com/v3/mail/send")
      .to_return(status: 202, body: "", headers: {})
  end

  describe ".process_batch" do
    it "transitions a pending job to done" do
      Worker.process_batch
      expect(job.reload.status).to eq("done")
    end

    it "creates dispatched and delivered audit entries" do
      Worker.process_batch
      statuses = NotificationAudit.where(event_id: event_rid).pluck(:status)
      expect(statuses).to include("dispatched", "delivered")
    end

    it "does not pick up jobs that are already done" do
      job.update!(status: "done")
      expect { Worker.process_batch }.not_to change(NotificationAudit, :count)
    end

    it "returns the count of jobs processed" do
      count = Worker.process_batch
      expect(count).to eq(1)
    end

    it "returns zero when no pending jobs are available" do
      job.update!(status: "done")
      expect(Worker.process_batch).to eq(0)
    end

    it "marks a job as failed when the referenced event does not exist" do
      job.update!(event_id: 9_999_999)
      Worker.process_batch
      expect(job.reload.status).to eq("failed")
      expect(job.reload.failed_reason).to match(/orphan_event/)
    end

    it "backs off a job on a transient failure (503)" do
      stub_request(:post, "https://api.sendgrid.com/v3/mail/send")
        .to_return(status: 503, body: "", headers: {})
      Worker.process_batch
      expect(job.reload.status).to eq("pending")
      expect(job.reload.attempts).to eq(1)
    end
  end

  describe ".process_batch SKIP LOCKED", :threads do
    it "concurrent workers claim disjoint sets of jobs" do
      event2 = create(:notification_event)
      job2   = create(:dispatch_queue, event_id: event2.attributes["id"])

      threads = 2.times.map { Thread.new { Worker.process_batch(batch_size: 1) } }
      threads.each(&:join)

      expect(job.reload.status).to eq("done")
      expect(job2.reload.status).to eq("done")
      expect(NotificationAudit.where(status: "delivered").count).to eq(2)
    end
  end
end
