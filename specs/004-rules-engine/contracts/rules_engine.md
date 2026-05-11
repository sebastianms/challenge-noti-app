# Contract — RulesEngine

```ruby
module Central::Decisioning
  class RulesEngine
    # Evalúa reglas para un evento y retorna un Decision.
    #
    # @param event [NotificationEvent] el evento recién persistido (capa A)
    # @return [Decision]
    #
    # Comportamiento:
    # - Si no existe regla para event.notification_type O regla está enabled=FALSE
    #     → Decision.dispatch (compatibilidad hacia atrás)
    # - Si regla.channels == []
    #     → Decision.filter(reason: "disabled", rule_id:)
    # - Si rate_limit_exceeded?(event, rule)
    #     → Decision.filter(reason: "rate_limited", rule_id:)
    # - Si in_cooldown?(event, rule)
    #     → Decision.filter(reason: "cooldown", rule_id:)
    # - Si regla.digest_window_seconds.present?
    #     → Decision.digest(rule_id:, window: regla.digest_window_seconds)
    # - else
    #     → Decision.dispatch(rule_id:, priority: regla.priority)
    def self.decide(event:); end
  end
end
```

## Pre-condiciones
- `event` está persistido en `notification_events`.
- `event.notification_type` y `event.recipient_canonical` están seteados.

## Post-condiciones
- Retorna siempre un `Decision` válido (nunca nil ni exception en flujo normal).
- No realiza side effects (no inserta en BD, no toca cache excepto leer).
- Idempotente: invocaciones repetidas con mismo evento retornan el mismo `Decision` (a menos que cambie estado externo: nueva fila en audit, regla modificada).

## Errores
- `RuleCache` puede levantar si la BD está caída — el `EventBuilder` decide cómo manejarlo (sugerencia: log y fallback a `Decision.dispatch` para no bloquear envíos críticos).
