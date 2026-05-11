# frozen_string_literal: true

class EmailChannel < ChannelStrategy
  def deliver(event, recipient_id, correlation_id:)
    unless recipient_id.to_s.include?("@")
      raise ArgumentError, "recipient_id must be an email address, got: #{recipient_id.inspect}"
    end

    SendgridAdapter.new.deliver(event, recipient_id, correlation_id: correlation_id)
  end

  def channel_name
    "email"
  end
end

ChannelRegistry.register(:email, EmailChannel.new)
