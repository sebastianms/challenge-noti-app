# frozen_string_literal: true

class Enqueuer
  def self.enqueue(event_id:, correlation_id:, recipient_canonical: nil, priority: :standard)
    DispatchQueue.create!(event_id: event_id, priority: priority.to_s, next_attempt_at: Time.current)
    NotificationAudit.create!(
      correlation_id:      correlation_id,
      event_id:            event_id,
      status:              "enqueued",
      source:              "internal",
      recipient_canonical: recipient_canonical
    )
  end
end
