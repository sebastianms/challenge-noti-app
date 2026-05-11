# frozen_string_literal: true

class ChannelStrategy
  def deliver(_event, _recipient_id, correlation_id:)
    raise NotImplementedError, "#{self.class} must implement #deliver"
  end

  def channel_name
    raise NotImplementedError, "#{self.class} must implement #channel_name"
  end
end
