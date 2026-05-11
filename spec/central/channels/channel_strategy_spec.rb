# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelStrategy do
  subject(:strategy) { ChannelStrategy.new }

  let(:event) { instance_double(NotificationEvent, notification_type: "test", payload: {}) }

  it "raises NotImplementedError when deliver is called on the base class" do
    expect { strategy.deliver(event, "user@example.com", correlation_id: "c1") }
      .to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError when channel_name is called on the base class" do
    expect { strategy.channel_name }
      .to raise_error(NotImplementedError)
  end
end
