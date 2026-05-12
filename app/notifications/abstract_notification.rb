# frozen_string_literal: true

class AbstractNotification
  class << self
    attr_reader :notification_type_id, :idempotency_window_value

    def notification_type(id)
      @notification_type_id = id.to_s
    end

    def idempotency_window(duration)
      @idempotency_window_value = duration
    end

    def resolved_notification_type
      @notification_type_id || name.underscore.delete_suffix("_notification")
    end

    def resolved_idempotency_window
      @idempotency_window_value || 1.minute
    end

    def title(_context = {})
      raise NotImplementedError, "#{name} must implement self.title(context = {})"
    end

    def body(_context = {})
      raise NotImplementedError, "#{name} must implement self.body(context = {})"
    end

    def digest_template(_items)
      nil
    end

    # @param recipient [String] email o user_id interno
    # @param context   [Hash]   datos del evento; context[:id] alimenta idempotencia
    # @param priority  [Symbol] :critical | :standard | :bulk
    # @return [SendResult]
    def send(recipient, context: {}, priority: :standard)
      EventBuilder.build(
        notification_class: self,
        recipient: recipient,
        context: resolved_context(context),
        priority: priority
      )
    end

    private

    def resolved_context(context)
      type = resolved_notification_type
      subject = Templates::TemplateResolver.title_for(type: type, ctx: context) || title(context)
      resolved_body = Templates::TemplateResolver.body_for(type: type, ctx: context) || body(context)
      context.merge(subject: subject, body: resolved_body)
    end
  end
end
