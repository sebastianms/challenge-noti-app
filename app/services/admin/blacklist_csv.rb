# frozen_string_literal: true

require "csv"

module Admin
  module BlacklistCsv
    HEADERS = %w[id recipient_canonical scope target source reason created_at].freeze

    def self.generate(items)
      CSV.generate(headers: true) do |csv|
        csv << HEADERS
        items.each do |entry|
          csv << [
            entry.id,
            entry.recipient_canonical,
            entry.scope,
            entry.target,
            entry.source,
            entry.reason,
            entry.created_at&.iso8601
          ]
        end
      end
    end
  end
end
