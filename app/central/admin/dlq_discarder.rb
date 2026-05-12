# frozen_string_literal: true

module Admin
  class DlqDiscarder
    def self.call(job, reason:, by:)
      raise ArgumentError, "reason is required" if reason.blank?

      ActiveRecord::Base.transaction do
        job.update!(status: "discarded")
        NotificationAudit.create!(
          correlation_id:    SecureRandom.uuid,
          status:            "dlq_discarded",
          channel:           "email",
          source:            "internal",
          notification_type: "_dlq_discarded_",
          metadata:          { discarded_by: by, reason: reason, job_id: job.id }
        )
      end
    end
  end
end
