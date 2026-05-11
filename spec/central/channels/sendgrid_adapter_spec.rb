# frozen_string_literal: true

require "rails_helper"

RSpec.describe SendgridAdapter do
  subject(:adapter) { SendgridAdapter.new }

  let(:event) do
    instance_double(
      NotificationEvent,
      notification_type: "password_reset",
      payload:           { "subject" => "Reset your password", "body" => "Click here to reset." }
    )
  end
  let(:recipient_email) { "user@example.com" }
  let(:correlation_id)  { "abc-123-def" }

  before do
    stub_request(:post, "https://api.sendgrid.com/v3/mail/send")
      .to_return(status: 202, body: "", headers: {})
  end

  describe "#deliver" do
    it "returns :delivered on a 202 response" do
      expect(adapter.deliver(event, recipient_email, correlation_id: correlation_id)).to eq(:delivered)
    end

    it "raises TransientError on a 503 response" do
      stub_request(:post, "https://api.sendgrid.com/v3/mail/send")
        .to_return(status: 503, body: "", headers: {})

      expect { adapter.deliver(event, recipient_email, correlation_id: correlation_id) }
        .to raise_error(TransientError)
    end

    it "raises PermanentError on a 400 response" do
      stub_request(:post, "https://api.sendgrid.com/v3/mail/send")
        .to_return(status: 400, body: "", headers: {})

      expect { adapter.deliver(event, recipient_email, correlation_id: correlation_id) }
        .to raise_error(PermanentError)
    end

    it "includes X-Correlation-ID header in the HTTP request" do
      adapter.deliver(event, recipient_email, correlation_id: correlation_id)

      expect(WebMock).to have_requested(:post, "https://api.sendgrid.com/v3/mail/send")
        .with(headers: { "X-Correlation-ID" => correlation_id })
    end

    it "includes subject in the request payload" do
      adapter.deliver(event, recipient_email, correlation_id: correlation_id)

      expect(WebMock).to have_requested(:post, "https://api.sendgrid.com/v3/mail/send")
        .with(body: hash_including("subject" => "Reset your password"))
    end

    it "includes content in the request payload" do
      adapter.deliver(event, recipient_email, correlation_id: correlation_id)

      expect(WebMock).to have_requested(:post, "https://api.sendgrid.com/v3/mail/send")
        .with(body: hash_including("content" => array_including(hash_including("value" => "Click here to reset."))))
    end

    it "includes recipient email in the to field" do
      adapter.deliver(event, recipient_email, correlation_id: correlation_id)

      expect(WebMock).to have_requested(:post, "https://api.sendgrid.com/v3/mail/send")
        .with(body: hash_including("personalizations" => array_including(
          hash_including("to" => [ { "email" => recipient_email } ])
        )))
    end

    it "includes a from field in the request payload" do
      adapter.deliver(event, recipient_email, correlation_id: correlation_id)

      expect(WebMock).to have_requested(:post, "https://api.sendgrid.com/v3/mail/send")
        .with(body: hash_including("from" => hash_including("email")))
    end
  end
end
