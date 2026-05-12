# frozen_string_literal: true

module Templates
  module TemplateCache
    TTL = 5.minutes

    def self.fetch(type, locale, &block)
      Rails.cache.fetch(cache_key(type, locale), expires_in: TTL, &block)
    end

    def self.invalidate(type, locale)
      Rails.cache.delete(cache_key(type, locale))
    end

    def self.cache_key(type, locale)
      "notification_template/#{type}/#{locale}"
    end
    private_class_method :cache_key
  end
end
