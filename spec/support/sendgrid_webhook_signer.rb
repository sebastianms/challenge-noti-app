# frozen_string_literal: true

require "ed25519"
require "base64"

module SendgridWebhookSigner
  def self.generate_keypair
    signing_key = Ed25519::SigningKey.generate
    {
      signing_key:    signing_key,
      verify_key:     signing_key.verify_key,
      public_key_b64: Base64.strict_encode64(signing_key.verify_key.to_bytes)
    }
  end

  def self.sign(payload:, timestamp:, signing_key:)
    Base64.strict_encode64(signing_key.sign("#{timestamp}#{payload}"))
  end

  def self.delivered_event(email: "user@example.com", correlation_id: nil)
    base = { "event" => "delivered", "email" => email, "timestamp" => Time.current.to_i, "sg_event_id" => SecureRandom.uuid }
    base["correlation_id"] = correlation_id if correlation_id
    base
  end

  def self.bounce_event(email: "user@example.com", bounce_type: "hard")
    { "event" => "bounce", "email" => email, "timestamp" => Time.current.to_i, "sg_event_id" => SecureRandom.uuid, "type" => bounce_type }
  end

  def self.spam_event(email: "user@example.com")
    { "event" => "spamreport", "email" => email, "timestamp" => Time.current.to_i, "sg_event_id" => SecureRandom.uuid }
  end
end
