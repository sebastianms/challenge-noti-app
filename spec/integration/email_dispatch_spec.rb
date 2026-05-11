# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Email dispatch pipeline", type: :integration do
  let(:recipient_email) { "user@example.com" }
  let(:context)         { { subject: "Happy Birthday", body: "Enjoy your day!" } }

  before do
    stub_request(:post, "https://api.sendgrid.com/v3/mail/send")
      .to_return(status: 202, body: "", headers: {})
  end

  describe "happy path" do
    let!(:result) { freeze_time { BirthdayNotification.send(recipient_email, context: context) } }

    it "marks the dispatch_queue job as done after process_batch" do
      Worker.process_batch
      expect(DispatchQueue.last.status).to eq("done")
    end

    it "creates audit entries in order: enqueued → dispatched → delivered" do
      Worker.process_batch
      statuses = NotificationAudit.where(correlation_id: result.correlation_id).order(:created_at).pluck(:status)
      expect(statuses).to eq(%w[enqueued dispatched delivered])
    end

    it "propagates X-Correlation-ID to the Sendgrid HTTP request" do
      Worker.process_batch
      expect(WebMock).to have_requested(:post, "https://api.sendgrid.com/v3/mail/send")
        .with(headers: { "X-Correlation-ID" => result.correlation_id })
    end
  end

  describe "idempotency" do
    it "returns :created on the first send" do
      result = freeze_time { BirthdayNotification.send(recipient_email, context: context) }
      expect(result.state).to eq(:created)
    end

    it "returns :duplicate on a repeated send within the same window" do
      freeze_time do
        BirthdayNotification.send(recipient_email, context: context)
        second = BirthdayNotification.send(recipient_email, context: context)
        expect(second.state).to eq(:duplicate)
      end
    end

    it "does not create an additional dispatch_queue job for a duplicate event" do
      freeze_time do
        BirthdayNotification.send(recipient_email, context: context)
        expect {
          BirthdayNotification.send(recipient_email, context: context)
        }.not_to change(DispatchQueue, :count)
      end
    end
  end
end
