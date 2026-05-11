# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailChannel do
  subject(:channel) { EmailChannel.new }

  let(:event) do
    instance_double(
      NotificationEvent,
      notification_type: "birthday",
      payload:           { "subject" => "Happy Birthday", "body" => "Have a great day!" }
    )
  end
  let(:correlation_id) { "corr-xyz-789" }

  before do
    stub_request(:post, "https://api.sendgrid.com/v3/mail/send")
      .to_return(status: 202, body: "", headers: {})
  end

  describe "#channel_name" do
    it "returns 'email'" do
      expect(channel.channel_name).to eq("email")
    end
  end

  describe "#deliver" do
    it "returns :delivered for a valid email recipient" do
      result = channel.deliver(event, "user@example.com", correlation_id: correlation_id)
      expect(result).to eq(:delivered)
    end

    it "raises ArgumentError when recipient_id has no @" do
      expect { channel.deliver(event, "not-an-email", correlation_id: correlation_id) }
        .to raise_error(ArgumentError)
    end

    it "includes the invalid recipient in the ArgumentError message" do
      expect { channel.deliver(event, "invalid", correlation_id: correlation_id) }
        .to raise_error(ArgumentError, /invalid/)
    end

    it "passes the correlation_id to SendgridAdapter" do
      channel.deliver(event, "user@example.com", correlation_id: correlation_id)

      expect(WebMock).to have_requested(:post, "https://api.sendgrid.com/v3/mail/send")
        .with(headers: { "X-Correlation-ID" => correlation_id })
    end

    it "delegates to SendgridAdapter with the recipient email" do
      channel.deliver(event, "user@example.com", correlation_id: correlation_id)

      expect(WebMock).to have_requested(:post, "https://api.sendgrid.com/v3/mail/send")
        .with(body: hash_including("personalizations" => array_including(
          hash_including("to" => [ { "email" => "user@example.com" } ])
        )))
    end
  end
end
