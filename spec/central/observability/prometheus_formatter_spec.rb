# frozen_string_literal: true

require "rails_helper"

RSpec.describe Observability::PrometheusFormatter do
  subject(:formatter) { described_class.new }

  let(:metrics) do
    {
      queue_depth:              42,
      dlq_size:                 7,
      events_ingested_24h:      18_432,
      dispatch_errors_by_class: { "TransientError" => 4, "PermanentError" => 2 },
      bounce_rate_5m:           0.012,
      webhook_lag_seconds:      3.5
    }
  end

  describe "#format" do
    subject(:output) { formatter.format(metrics) }

    it "includes HELP and TYPE lines for each metric" do
      expect(output).to include("# HELP notif_queue_depth")
      expect(output).to include("# TYPE notif_queue_depth gauge")
      expect(output).to include("# HELP notif_dlq_size")
      expect(output).to include("# HELP notif_events_ingested_total")
      expect(output).to include("# HELP notif_dispatch_errors_total")
      expect(output).to include("# HELP notif_bounce_rate_5m")
      expect(output).to include("# HELP notif_webhook_lag_seconds")
    end

    it "renders scalar gauge values" do
      expect(output).to include("notif_queue_depth 42")
      expect(output).to include("notif_dlq_size 7")
      expect(output).to include("notif_events_ingested_total 18432")
      expect(output).to include("notif_bounce_rate_5m 0.012")
      expect(output).to include("notif_webhook_lag_seconds 3.5")
    end

    it "renders labeled gauges for dispatch_errors_by_class" do
      expect(output).to include('notif_dispatch_errors_total{class="TransientError"} 4')
      expect(output).to include('notif_dispatch_errors_total{class="PermanentError"} 2')
    end

    it "renders empty hash as no data lines (only HELP/TYPE)" do
      result = formatter.format(metrics.merge(dispatch_errors_by_class: {}))

      lines = result.lines.map(&:chomp)
      data_lines = lines.select { |l| l.start_with?("notif_dispatch_errors_total{") }
      expect(data_lines).to be_empty
    end
  end
end
