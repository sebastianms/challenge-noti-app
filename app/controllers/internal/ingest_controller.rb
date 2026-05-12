# frozen_string_literal: true

module Internal
  class IngestController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :check_load_test_enabled
    before_action :authenticate_load_test

    def create
      body      = request.raw_post
      params    = JSON.parse(body)
      recipient  = params["recipient"].presence
      context_id = params["context_id"].presence || SecureRandom.hex(8)

      return render json: { error: "recipient required" }, status: :bad_request unless recipient

      result = LoadTestNotification.send(recipient, context: { id: context_id })
      render json: { state: result.state, correlation_id: result.correlation_id }, status: :created
    rescue JSON::ParserError
      render json: { error: "invalid JSON" }, status: :bad_request
    end

    private

    def check_load_test_enabled
      return if LoadTestAuth::ENABLED

      render json: { error: "load test ingest not enabled" }, status: :service_unavailable
    end

    def authenticate_load_test
      authenticate_or_request_with_http_basic("LoadTest") do |name, pass|
        ActiveSupport::SecurityUtils.secure_compare(name, LoadTestAuth::USER.to_s) &
          ActiveSupport::SecurityUtils.secure_compare(pass, LoadTestAuth::PASSWORD.to_s)
      end
    end
  end
end
