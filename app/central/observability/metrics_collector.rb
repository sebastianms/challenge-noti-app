# frozen_string_literal: true

module Observability
  class MetricsCollector
    def queue_depth
      DispatchQueue.where(status: %w[pending in_flight]).count
    end

    def dlq_size
      DispatchQueue.where(status: "failed").count
    end

    def events_ingested_24h
      NotificationEvent.where("created_at >= ?", 24.hours.ago).count
    end

    def dispatch_errors_by_class
      DispatchQueue.where(status: "failed")
        .select("split_part(COALESCE(failed_reason, ''), ':', 1) AS reason_class, COUNT(*) AS count")
        .group("reason_class")
        .each_with_object({}) do |row, hash|
          key = row.reason_class.presence || "Unknown"
          hash[key] = row.count.to_i
        end
    end

    def bounce_rate_5m
      window = 5.minutes.ago
      scope  = NotificationAudit.where(source: "sendgrid_webhook", created_at: window..)
      total  = scope.count
      return 0.0 if total.zero?

      bounces = scope.where(status: "bounced").count
      (bounces.to_f / total).round(4)
    end

    def webhook_lag_seconds
      oldest = WebhookEvent.where(status: %w[pending processing]).minimum(:received_at)
      return 0.0 unless oldest

      (Time.current - oldest).round(1)
    end

    def collect
      {
        queue_depth:            queue_depth,
        dlq_size:               dlq_size,
        events_ingested_24h:    events_ingested_24h,
        dispatch_errors_by_class: dispatch_errors_by_class,
        bounce_rate_5m:         bounce_rate_5m,
        webhook_lag_seconds:    webhook_lag_seconds
      }
    end
  end
end
