# frozen_string_literal: true

# Fixtures de notificaciones para uso en tests. No se deben enviar realmente.

class BirthdayNotification < AbstractNotification
  notification_type :birthday

  def self.title(context = {})
    "¡Feliz cumpleaños, #{context[:name]}!"
  end

  def self.body(_context = {})
    "Hoy te deseamos un excelente día."
  end
end

class InvoicePaidNotification < AbstractNotification
  notification_type :invoice_paid
  idempotency_window 1.hour

  def self.title(_context = {})
    "Tu factura fue pagada"
  end

  def self.body(context = {})
    "La factura ##{context[:invoice_id]} fue procesada exitosamente."
  end
end

# Subclase intencionalmente rota: no implementa title ni body.
class BrokenNotification < AbstractNotification
end
