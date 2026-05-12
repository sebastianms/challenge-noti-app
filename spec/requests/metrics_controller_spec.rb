# frozen_string_literal: true

require "rails_helper"
require "benchmark"

RSpec.describe "GET /metrics", type: :request do
  let(:user)        { "scraper" }
  let(:password)    { "s3cr3t" }
  let(:credentials) { ActionController::HttpAuthentication::Basic.encode_credentials(user, password) }
  let(:headers)     { { "Authorization" => credentials } }

  before do
    stub_const("MetricsAuth::USER",                user)
    stub_const("MetricsAuth::PASSWORD",            password)
    stub_const("MetricsAuth::CREDENTIALS_PRESENT", true)
    stub_const("MetricsAuth::CREDENTIALS",         [ user, password ].freeze)
  end

  describe "200 OK with valid auth" do
    before { get "/metrics", headers: headers }

    it "returns 200" do
      expect(response).to have_http_status(:ok)
    end

    it "uses prometheus content type" do
      expect(response.content_type).to include("text/plain")
    end

    it "includes all expected metric names" do
      %w[
        notif_queue_depth
        notif_dlq_size
        notif_events_ingested_total
        notif_dispatch_errors_total
        notif_bounce_rate_5m
        notif_webhook_lag_seconds
      ].each do |metric|
        expect(response.body).to include(metric)
      end
    end

    it "includes HELP and TYPE lines" do
      expect(response.body).to include("# HELP")
      expect(response.body).to include("# TYPE")
    end

    it "sets Cache-Control header" do
      expect(response.headers["Cache-Control"]).to include("max-age=5")
    end
  end

  describe "401 without auth" do
    it "returns 401" do
      get "/metrics"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "503 when credentials not configured" do
    before { stub_const("MetricsAuth::CREDENTIALS_PRESENT", false) }

    it "returns 503 and safe body" do
      get "/metrics", headers: headers

      expect(response).to have_http_status(:service_unavailable)
      expect(response.body).to eq("# metrics unavailable\n")
    end
  end

  describe "performance" do
    it "responds in under 100ms with 10k dispatch_queue rows" do
      DispatchQueue.insert_all(
        Array.new(10_000) do |i|
          {
            event_id:        i + 1,
            priority:        "standard",
            status:          "pending",
            attempts:        0,
            next_attempt_at: Time.current,
            created_at:      Time.current,
            updated_at:      Time.current
          }
        end
      )

      elapsed = Benchmark.realtime { get "/metrics", headers: headers }

      expect(elapsed).to be < 0.1
    end
  end
end
