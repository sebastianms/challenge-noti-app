# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelRegistry do
  let(:test_channel) { instance_double(ChannelStrategy) }

  before { ChannelRegistry.register(:__test__, test_channel) }

  it "retrieves a registered channel by symbol" do
    expect(ChannelRegistry.for(:__test__)).to eq(test_channel)
  end

  it "retrieves a registered channel by string name" do
    expect(ChannelRegistry.for("__test__")).to eq(test_channel)
  end

  it "raises KeyError for an unknown channel" do
    expect { ChannelRegistry.for(:__nonexistent__) }.to raise_error(KeyError)
  end

  it "registered_names includes the registered channel" do
    expect(ChannelRegistry.registered_names).to include(:__test__)
  end

  it "register normalizes string name to symbol" do
    ChannelRegistry.register("__str_test__", test_channel)
    expect(ChannelRegistry.for(:__str_test__)).to eq(test_channel)
  end
end
