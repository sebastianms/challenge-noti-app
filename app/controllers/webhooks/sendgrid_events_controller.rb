# frozen_string_literal: true

module Webhooks
  class SendgridEventsController < ActionController::API
    SIGNATURE_HEADER = "HTTP_X_TWILIO_EMAIL_EVENT_WEBHOOK_SIGNATURE"
    TIMESTAMP_HEADER = "HTTP_X_TWILIO_EMAIL_EVENT_WEBHOOK_TIMESTAMP"

    def create
      signature = request.headers[SIGNATURE_HEADER]
      timestamp = request.headers[TIMESTAMP_HEADER]
      raw_body  = request.raw_post

      return render(json: { error: "missing_signature_headers" }, status: :unauthorized) if signature.blank? || timestamp.blank?

      unless SendgridSignature.verify(payload: raw_body, signature: signature, timestamp: timestamp, public_key: public_key)
        return render(json: { error: "invalid_signature" }, status: :unauthorized)
      end

      parsed = JSON.parse(raw_body)
      events = parsed.is_a?(Array) ? parsed : [ parsed ]

      we = WebhookEvent.create!(
        source:       "sendgrid",
        payload:      events,
        signature:    signature,
        signature_ts: timestamp,
        status:       "pending",
        received_at:  Time.current
      )

      render json: { received: events.size, webhook_event_id: we.id }, status: :ok
    rescue JSON::ParserError
      render json: { error: "invalid_json" }, status: :bad_request
    rescue SendgridSignature::MissingPublicKey
      render json: { error: "public_key_not_configured" }, status: :service_unavailable
    end

    private

    def public_key
      ENV["SENDGRID_WEBHOOK_PUBLIC_KEY"]
    end
  end
end
