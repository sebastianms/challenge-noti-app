# frozen_string_literal: true

require "csv"

module Admin
  module AuditCsv
    HEADERS = %w[correlation_id status channel source notification_type recipient_canonical reason rule_id created_at].freeze

    def self.generate(items)
      CSV.generate(headers: true) do |csv|
        csv << HEADERS
        items.each do |audit|
          csv << [
            audit.correlation_id,
            audit.status,
            audit.channel,
            audit.source,
            audit.notification_type,
            audit.recipient_canonical,
            audit.metadata&.dig("reason"),
            audit.metadata&.dig("rule_id"),
            audit.created_at&.iso8601
          ]
        end
      end
    end
  end
end
