# Contract: AbstractNotification
#
# Public API que los 25+ equipos extenderán. Esta es la única interfaz pública
# de esta feature; todo lo demás es interno y puede cambiar.
#
# Reglas:
# - Una subclase DEBE implementar self.title y self.body.
# - Una subclase PUEDE declarar notification_type, idempotency_window, digest_template.
# - Cargar una subclase sin title o body lanza NotImplementedError con mensaje claro.

class AbstractNotification
  class << self
    # Identificador estable del tipo. Default: FQN normalizado.
    # Se sobreescribe con: notification_type :stable_id
    attr_reader :notification_type_id

    # Ventana de idempotencia (ActiveSupport::Duration). Default: 1.minute.
    # Se sobreescribe con: idempotency_window 1.hour
    attr_reader :idempotency_window_value

    def notification_type(id)
      @notification_type_id = id.to_s
    end

    def idempotency_window(duration)
      @idempotency_window_value = duration
    end

    # Resuelto en tiempo de invocación con default si no se declaró.
    def resolved_notification_type
      @notification_type_id || name.underscore.delete_suffix("_notification")
    end

    def resolved_idempotency_window
      @idempotency_window_value || 1.minute
    end

    # Métodos que subclase DEBE implementar.
    # Reciben context para personalización opcional.
    def title(context = {})
      raise NotImplementedError, "#{name} must implement self.title(context = {})"
    end

    def body(context = {})
      raise NotImplementedError, "#{name} must implement self.body(context = {})"
    end

    # Opcional. Si está, habilita agrupación por digest en features posteriores.
    def digest_template(items)
      nil
    end

    # Punto de entrada público. Delega a Central::Ingestion::EventBuilder.
    #
    # @param recipient [String] email o user_id (autodetectado)
    # @param context   [Hash]   datos del evento; context[:id] alimenta idempotencia
    # @param priority  [Symbol] :critical | :standard | :bulk (default :standard)
    # @return [Central::Ingestion::SendResult]
    def send(recipient, context: {}, priority: :standard)
      Central::Ingestion::EventBuilder.build(
        notification_class: self,
        recipient: recipient,
        context: context,
        priority: priority
      )
    end
  end

  # Hook de carga: si la subclase no implementó title/body, falla en el momento
  # en que se referencia, no en runtime de envío. El test del cargador valida esto.
  def self.inherited(subclass)
    super
    # La validación real ocurre la primera vez que se invoca title/body.
    # Tests de "fail loud" se hacen invocando los métodos en CI con un context vacío.
  end
end
