# frozen_string_literal: true

require "digest"

class IdempotencyHash
  SEPARATOR = "|".freeze

  def self.compute(notification_type:, recipient_canonical:, context_id:, window_ts:)
    parts = [ notification_type, recipient_canonical, context_id, window_ts.iso8601 ]
    Digest::SHA256.hexdigest(parts.join(SEPARATOR))
  end
end
