# frozen_string_literal: true

module Admin
  class DlqRetrier
    CAP = 500

    def self.call(job, by:)
      ActiveRecord::Base.transaction do
        original_attempts = job.attempts
        job.update!(status: "pending", attempts: 0, next_attempt_at: Time.current, locked_at: nil)
        NotificationAudit.create!(
          correlation_id:    SecureRandom.uuid,
          status:            "dlq_retried",
          channel:           "email",
          source:            "internal",
          notification_type: "_dlq_retried_",
          metadata:          { retried_by: by, job_id: job.id, original_attempts: original_attempts }
        )
      end
    end

    def self.bulk_call(reason:, by:, cap: CAP)
      ids = DispatchQueue
        .where(status: "failed")
        .where("failed_reason LIKE ?", "#{reason}%")
        .order(:id)
        .limit(cap)
        .pluck(:id)

      return { retried: 0, total: 0 } if ids.empty?

      total = DispatchQueue
        .where(status: "failed")
        .where("failed_reason LIKE ?", "#{reason}%")
        .count

      ActiveRecord::Base.transaction do
        retried = DispatchQueue
          .where(id: ids, status: "failed")
          .update_all(status: "pending", attempts: 0, next_attempt_at: Time.current,
                      locked_at: nil, updated_at: Time.current)

        NotificationAudit.create!(
          correlation_id:    SecureRandom.uuid,
          status:            "dlq_bulk_retried",
          channel:           "email",
          source:            "internal",
          notification_type: "_dlq_bulk_retried_",
          metadata:          { retried_by: by, count: retried, reason_filter: reason }
        )
        { retried: retried, total: total }
      end
    end
  end
end
