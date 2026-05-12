# frozen_string_literal: true

class MetricsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :check_credentials_configured
  before_action :authenticate_metrics

  def show
    metrics = Observability::MetricsCollector.new.collect
    body    = Observability::PrometheusFormatter.new.format(metrics)

    response.set_header("Cache-Control", "public, max-age=5")
    render plain: body, content_type: "text/plain; version=0.0.4; charset=utf-8"
  rescue ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad
    render plain: "# metrics unavailable\n", status: :service_unavailable,
           content_type: "text/plain"
  end

  private

  def check_credentials_configured
    return if MetricsAuth::CREDENTIALS_PRESENT

    render plain: "# metrics unavailable\n", status: :service_unavailable,
           content_type: "text/plain"
  end

  def authenticate_metrics
    authenticate_or_request_with_http_basic("Metrics") do |name, pass|
      ActiveSupport::SecurityUtils.secure_compare(name, MetricsAuth::USER.to_s) &
        ActiveSupport::SecurityUtils.secure_compare(pass, MetricsAuth::PASSWORD.to_s)
    end
  end
end
