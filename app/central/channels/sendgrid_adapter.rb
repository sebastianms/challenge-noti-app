# frozen_string_literal: true

require "net/http"
require "json"

class SendgridAdapter
  SENDGRID_API_URL = URI("https://api.sendgrid.com/v3/mail/send")

  def deliver(event, recipient_email, correlation_id:)
    payload  = build_payload(event, recipient_email, correlation_id)
    response = post_to_sendgrid(payload, correlation_id)
    classify(response)
  end

  private

  def build_payload(event, recipient_email, correlation_id)
    event_payload = event.payload.is_a?(Hash) ? event.payload : JSON.parse(event.payload.to_s)
    subject = event_payload["subject"] || event.notification_type.to_s
    body    = event_payload["body"]    || subject
    {
      personalizations: [ { to: [ { email: recipient_email } ] } ],
      from:             { email: from_email },
      subject:          subject,
      content:          [ { type: "text/plain", value: body } ],
      # custom_args are persisted by SendGrid and included in webhook event payloads,
      # enabling correlation between SendGrid delivery events and our notification_audit records.
      custom_args:      { "correlation_id" => correlation_id.to_s }
    }
  end

  def post_to_sendgrid(payload, correlation_id)
    http          = Net::HTTP.new(SENDGRID_API_URL.host, SENDGRID_API_URL.port)
    http.use_ssl  = true

    request = Net::HTTP::Post.new(SENDGRID_API_URL.path)
    request["Authorization"]    = "Bearer #{api_key}"
    request["Content-Type"]     = "application/json"
    request["X-Correlation-ID"] = correlation_id.to_s
    request.body                = payload.to_json

    http.request(request)
  end

  def classify(response)
    case response.code.to_i
    when 200..299 then :delivered
    when 400..499 then raise PermanentError, "sendgrid_4xx: #{response.code}"
    else               raise TransientError, "sendgrid_5xx: #{response.code}"
    end
  end

  def api_key
    ENV.fetch("SENDGRID_API_KEY", "")
  end

  def from_email
    ENV.fetch("SENDGRID_FROM_EMAIL", "noreply@example.com")
  end
end
