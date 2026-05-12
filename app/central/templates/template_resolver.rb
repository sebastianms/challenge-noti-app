# frozen_string_literal: true

module Templates
  class TemplateResolver
    LOCALE = "es"

    def self.title_for(type:, ctx: {})
      resolve(:title, type, ctx)
    end

    def self.body_for(type:, ctx: {})
      resolve(:body, type, ctx)
    end

    def self.digest_for(type:, ctx: {})
      resolve(:digest_template, type, ctx)
    end

    def self.resolve(field, type, ctx)
      override = fetch_override(type)
      return nil if override.nil? || override[field].nil?

      Templates::TemplateInterpolator.interpolate(override[field], ctx)[:result]
    end
    private_class_method :resolve

    def self.fetch_override(type)
      TemplateCache.fetch(type, LOCALE) do
        record = NotificationTemplate.find_by(notification_type: type, locale: LOCALE)
        record ? { title: record.title, body: record.body, digest_template: record.digest_template } : nil
      end
    end
    private_class_method :fetch_override
  end
end
