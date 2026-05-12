# frozen_string_literal: true

module Observability
  class PrometheusFormatter
    METRIC_META = {
      queue_depth: {
        help: "Jobs pendientes de envío en dispatch_queue.",
        type: "gauge",
        name: "notif_queue_depth"
      },
      dlq_size: {
        help: "Jobs en estado failed (DLQ).",
        type: "gauge",
        name: "notif_dlq_size"
      },
      events_ingested_24h: {
        help: "Eventos ingestados en las últimas 24h (proxy de counter).",
        type: "gauge",
        name: "notif_events_ingested_total"
      },
      dispatch_errors_by_class: {
        help: "Jobs en DLQ agrupados por clase de error.",
        type: "gauge",
        name: "notif_dispatch_errors_total"
      },
      bounce_rate_5m: {
        help: "Tasa de bounces sobre total de envíos en últimos 5min.",
        type: "gauge",
        name: "notif_bounce_rate_5m"
      },
      webhook_lag_seconds: {
        help: "Edad en segundos del webhook_event más antiguo pendiente.",
        type: "gauge",
        name: "notif_webhook_lag_seconds"
      }
    }.freeze

    def format(metrics)
      lines = []
      METRIC_META.each_key do |key|
        meta  = METRIC_META[key]
        value = metrics[key]
        lines << "# HELP #{meta[:name]} #{meta[:help]}"
        lines << "# TYPE #{meta[:name]} #{meta[:type]}"
        if value.is_a?(Hash)
          value.each { |label, v| lines << "#{meta[:name]}{class=\"#{label}\"} #{v}" }
        else
          lines << "#{meta[:name]} #{value}"
        end
        lines << ""
      end
      lines.join("\n")
    end
  end
end
