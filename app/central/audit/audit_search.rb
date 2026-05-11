# frozen_string_literal: true

class AuditSearch
  def initialize(correlation_id:)
    @correlation_id = correlation_id
  end

  def call
    return [] if @correlation_id.blank?

    NotificationAudit
      .where(correlation_id: @correlation_id)
      .order(created_at: :asc)
      .to_a
  end
end
