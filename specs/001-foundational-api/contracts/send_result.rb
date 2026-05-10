# Contract: SendResult
#
# Valor de retorno de AbstractNotification.send.
# Es un value object inmutable que el integrador puede inspeccionar.

module Central
  module Ingestion
    class SendResult
      STATES = %i[created duplicate rejected].freeze

      attr_reader :state, :correlation_id, :reason

      def initialize(state:, correlation_id: nil, reason: nil)
        raise ArgumentError, "invalid state: #{state}" unless STATES.include?(state)

        @state = state
        @correlation_id = correlation_id
        @reason = reason
        freeze
      end

      def self.created(correlation_id:)
        new(state: :created, correlation_id: correlation_id)
      end

      def self.duplicate(correlation_id:)
        new(state: :duplicate, correlation_id: correlation_id)
      end

      def self.rejected(reason:)
        new(state: :rejected, reason: reason)
      end

      def created?    = state == :created
      def duplicate?  = state == :duplicate
      def rejected?   = state == :rejected
      def persisted?  = created? || duplicate?

      def to_h
        { state: state, correlation_id: correlation_id, reason: reason }.compact
      end
    end
  end
end

# Rationale:
# - :created y :duplicate AMBOS devuelven correlation_id (en duplicate es el del original).
#   Esto permite agrupar logs sin distinguir el caso.
# - :rejected NO devuelve correlation_id porque no hay evento persistido.
# - Nunca se levanta excepción por duplicado; solo por inputs inválidos antes de persistir.
# - El objeto es frozen para evitar mutaciones accidentales en el código del integrador.
