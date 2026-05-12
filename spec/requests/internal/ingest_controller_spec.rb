# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /internal/ingest", type: :request do
  let(:user)        { "loadtest" }
  let(:password)    { "secret" }
  let(:credentials) { ActionController::HttpAuthentication::Basic.encode_credentials(user, password) }
  let(:headers)     { { "Authorization" => credentials, "Content-Type" => "application/json" } }

  before do
    stub_const("LoadTestAuth::USER",    user)
    stub_const("LoadTestAuth::PASSWORD", password)
    stub_const("LoadTestAuth::ENABLED",  true)
  end

  describe "201 Created with valid payload" do
    it "accepts a minimal payload and returns state + correlation_id" do
      post "/internal/ingest",
           params: { recipient: "test@example.com", context_id: "ctx-1" }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body).to include("state", "correlation_id")
    end
  end

  describe "400 Bad Request" do
    it "returns 400 when recipient is missing" do
      post "/internal/ingest",
           params: { context_id: "ctx-1" }.to_json,
           headers: headers

      expect(response).to have_http_status(:bad_request)
    end

    it "returns 400 when body is not valid JSON" do
      post "/internal/ingest",
           params: "not-json",
           headers: headers

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "401 Unauthorized" do
    it "returns 401 without auth" do
      post "/internal/ingest",
           params: { recipient: "test@example.com" }.to_json,
           headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "503 when load test not enabled" do
    before { stub_const("LoadTestAuth::ENABLED", false) }

    it "returns 503" do
      post "/internal/ingest",
           params: { recipient: "test@example.com" }.to_json,
           headers: headers

      expect(response).to have_http_status(:service_unavailable)
    end
  end
end
