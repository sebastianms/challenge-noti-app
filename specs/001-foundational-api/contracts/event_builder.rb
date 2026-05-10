# Contract: EventBuilder
#
# Componente interno que orquesta:
#   1. Validación y normalización del recipient.
#   2. Cálculo del idempotency_hash.
#   3. INSERT ... ON CONFLICT DO NOTHING en notification_events.
#   4. Retorno del SendResult tipado.
#
# Es el ÚNICO camino de escritura a notification_events. Cualquier otra
# escritura es un bug.

module Central
  module Ingestion
    class EventBuilder
      # @param notification_class [Class<AbstractNotification>]
      # @param recipient [String]
      # @param context [Hash] context del integrador; context[:id] o el primer ID detectado
      #                       se usa como context_id en el hash. El resto va al payload.
      # @param priority [Symbol]
      # @return [SendResult]
      def self.build(notification_class:, recipient:, context: {}, priority: :standard)
        new(notification_class, recipient, context, priority).call
      end

      def initialize(notification_class, recipient, context, priority)
        @notification_class = notification_class
        @recipient_input = recipient
        @context = context || {}
        @priority = priority
      end

      def call
        normalized = RecipientNormalizer.normalize(@recipient_input)

        type_id = @notification_class.resolved_notification_type
        window = @notification_class.resolved_idempotency_window
        window_ts = floor_to_window(Time.current.utc, window)
        context_id = extract_context_id(@context)

        hash = IdempotencyHash.compute(
          notification_type: type_id,
          recipient_canonical: normalized[:canonical],
          context_id: context_id,
          window_ts: window_ts
        )

        persist(
          notification_type: type_id,
          recipient_canonical: normalized[:canonical],
          recipient_type: normalized[:type].to_s,
          context_id: context_id,
          payload: serialize_payload(@context),
          idempotency_hash: hash,
          idempotency_window_ts: window_ts
        )
      rescue ArgumentError => e
        SendResult.rejected(reason: e.message)
      end

      private

      def floor_to_window(time, window)
        seconds = window.to_i
        Time.at((time.to_i / seconds) * seconds).utc
      end

      def extract_context_id(context)
        return "no_context" if context.empty?

        # Convención: si el integrador pasa context: { id: X }, X es el context_id.
        # Si no, usamos el primer valor escalar como heurística estable.
        candidate = context[:id] || context.values.find { |v| v.is_a?(String) || v.is_a?(Integer) }
        return "no_context" if candidate.nil?

        candidate.to_s
      end

      def serialize_payload(context)
        # Falla temprano si el payload no es JSON-serializable.
        JSON.generate(context)
        context.deep_stringify_keys
      rescue JSON::GeneratorError, Encoding::UndefinedConversionError => e
        raise ArgumentError, "context not JSON-serializable: #{e.message}"
      end

      def persist(attrs)
        sql = <<~SQL.squish
          INSERT INTO notification_events
            (notification_type, recipient_canonical, recipient_type, context_id,
             payload, idempotency_hash, idempotency_window_ts)
          VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7)
          ON CONFLICT (idempotency_hash, idempotency_window_ts) DO NOTHING
          RETURNING correlation_id;
        SQL

        result = Central::NotificationEvent.connection.exec_query(
          sql,
          "EventBuilder.persist",
          [
            attrs[:notification_type],
            attrs[:recipient_canonical],
            attrs[:recipient_type],
            attrs[:context_id],
            JSON.generate(attrs[:payload]),
            attrs[:idempotency_hash],
            attrs[:idempotency_window_ts]
          ]
        )

        if result.rows.any?
          SendResult.created(correlation_id: result.rows.first.first)
        else
          existing = Central::NotificationEvent
            .where(idempotency_hash: attrs[:idempotency_hash])
            .order(created_at: :desc)
            .limit(1)
            .pick(:correlation_id)
          SendResult.duplicate(correlation_id: existing)
        end
      end
    end
  end
end
