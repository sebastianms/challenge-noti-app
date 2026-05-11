# frozen_string_literal: true

require "rails_helper"

RSpec.describe SendgridSignature do
  let(:keypair)   { SendgridWebhookSigner.generate_keypair }
  let(:payload)   { '[{"event":"delivered","email":"u@e.com"}]' }
  let(:timestamp) { "1700000000" }
  let(:signature) { SendgridWebhookSigner.sign(payload: payload, timestamp: timestamp, signing_key: keypair[:signing_key]) }

  it "returns true for a valid signature" do
    expect(SendgridSignature.verify(
      payload:    payload,
      signature:  signature,
      timestamp:  timestamp,
      public_key: keypair[:public_key_b64]
    )).to be true
  end

  it "returns false for an invalid signature" do
    other = SendgridWebhookSigner.generate_keypair
    bad_sig = SendgridWebhookSigner.sign(payload: payload, timestamp: timestamp, signing_key: other[:signing_key])
    expect(SendgridSignature.verify(
      payload:    payload,
      signature:  bad_sig,
      timestamp:  timestamp,
      public_key: keypair[:public_key_b64]
    )).to be false
  end

  it "returns false when timestamp is tampered" do
    expect(SendgridSignature.verify(
      payload:    payload,
      signature:  signature,
      timestamp:  "9999999999",
      public_key: keypair[:public_key_b64]
    )).to be false
  end

  it "returns false when payload is tampered" do
    expect(SendgridSignature.verify(
      payload:    "#{payload}TAMPERED",
      signature:  signature,
      timestamp:  timestamp,
      public_key: keypair[:public_key_b64]
    )).to be false
  end

  it "raises MissingPublicKey when public_key is blank" do
    expect {
      SendgridSignature.verify(payload: payload, signature: signature, timestamp: timestamp, public_key: "")
    }.to raise_error(SendgridSignature::MissingPublicKey)
  end
end
