# frozen_string_literal: true

# Contrato público que todo canal debe implementar.
# No es una clase Ruby real — es documentación ejecutable del contrato.
#
# Cada implementación:
#   - Recibe el evento completo y el recipient_id ya normalizado.
#   - Devuelve un símbolo: :delivered | :failed.
#   - Levanta ArgumentError si los datos son inválidos (error permanente, va a DLQ sin reintentos).
#   - Propaga el correlation_id al proveedor vía header o metadata.
#
# Uso:
#   Central::Channels::ChannelRegistry.register(:email, EmailChannel.new)
#   channel = Central::Channels::ChannelRegistry.for(:email)
#   result  = channel.deliver(event, recipient_id)

module Central
  module Channels
    class ChannelStrategy
      # @param event [NotificationEvent]
      # @param recipient_id [String] email o user_id ya normalizado
      # @return [:delivered, :failed]
      # @raise [ArgumentError] si el recipient no es compatible con este canal
      def deliver(event, recipient_id)
        raise NotImplementedError, "#{self.class}#deliver no implementado"
      end

      # @return [String] nombre del canal para auditoría (ej. "email")
      def channel_name
        raise NotImplementedError, "#{self.class}#channel_name no implementado"
      end
    end
  end
end
