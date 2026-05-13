# frozen_string_literal: true

module Admin
  class DashboardMetrics
    CACHE_KEY = "admin/dashboard_snapshot"
    CACHE_TTL = 30.seconds

    def snapshot
      cached_metrics.merge(
        queue_depth: queue_depth,
        dlq_depth:   dlq_depth
      )
    end

    private

    def cached_metrics
      Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) do
        { volume: volume, filter_rate: filter_rate, error_rate: error_rate,
          volume_by_type: volume_by_type, volume_by_channel: volume_by_channel }
      end
    end

    def volume
      NotificationEvent.group_by_day(:created_at, last: 7).count
    end

    def volume_by_type
      NotificationAudit.where("created_at >= ?", 7.days.ago)
                       .group(:notification_type)
                       .count
                       .transform_keys { |k| k.presence || "(sin tipo)" }
    end

    def volume_by_channel
      NotificationAudit.where("created_at >= ?", 7.days.ago)
                       .group(:channel)
                       .count
    end

    def filter_rate
      NotificationAudit.group(:status).count
    end

    def error_rate
      NotificationAudit.where(status: "failed").group(:notification_type).count
    end

    def queue_depth
      DispatchQueue.where(status: "pending").count
    end

    def dlq_depth
      DispatchQueue.where(status: "failed").count
    end
  end
end
