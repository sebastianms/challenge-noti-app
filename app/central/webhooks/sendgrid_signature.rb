# frozen_string_literal: true

require "ed25519"
require "base64"

module SendgridSignature
  MissingPublicKey = Class.new(StandardError)

  def self.verify(payload:, signature:, timestamp:, public_key:)
    raise MissingPublicKey, "SENDGRID_WEBHOOK_PUBLIC_KEY is not configured" if public_key.blank?

    key_bytes = Base64.decode64(public_key)
    verify_key = Ed25519::VerifyKey.new(key_bytes)
    signed_payload = "#{timestamp}#{payload}"
    sig_bytes = Base64.decode64(signature)

    verify_key.verify(sig_bytes, signed_payload)
    true
  rescue Ed25519::VerifyError, ArgumentError
    false
  end
end
