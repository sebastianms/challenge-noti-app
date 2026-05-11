# frozen_string_literal: true

class ChannelRegistry
  @registry = {}

  class << self
    def register(name, channel)
      @registry[name.to_sym] = channel
    end

    def for(name)
      @registry.fetch(name.to_sym) { raise KeyError, "unknown channel: #{name}" }
    end

    def registered_names
      @registry.keys
    end
  end
end
