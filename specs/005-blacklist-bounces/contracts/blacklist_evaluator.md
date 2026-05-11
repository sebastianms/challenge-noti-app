# Contract — `Central::Decisioning::BlacklistEvaluator`

## Interfaz

```ruby
module Central::Decisioning
  class BlacklistEvaluator
    # Devuelve la fila de blacklist que filtra el evento, o nil si no hay match.
    #
    # @param event [#recipient_canonical, #notification_type, #channel]
    #   El channel se infiere del Decision si está disponible; default "email".
    # @return [NotificationBlacklist, nil]
    def self.match(event:, channel: "email")
    end

    # Predicado conveniencia (false si match es nil).
    def self.blacklisted?(event:, channel: "email")
      !match(event: event, channel: channel).nil?
    end
  end
end
```

## Comportamiento

1. Toma `recipient_canonical`, `notification_type`, `channel` del evento.
2. Ejecuta query única OR con LIMIT 1 (ver R2 de research.md).
3. Si encuentra fila → la retorna. Si no → `nil`.
4. Errores de DB se propagan (no se silencian).

## Integración con `EventBuilder`

```ruby
# app/central/ingestion/event_builder.rb
def perform
  return :duplicate if duplicate?

  if (entry = BlacklistEvaluator.match(event: event_obj))
    audit_filtered(reason: "blacklisted", metadata: { blacklist_id: entry.id, scope: entry.scope, target: entry.target })
    return SendResult.filtered(correlation_id: correlation_id)
  end

  decision = RulesEngine.decide(event: event_obj)
  apply_decision(decision)
end
```

## Tests requeridos

- `blacklist_evaluator_spec.rb`:
  - sin fila → `nil`
  - fila `scope=global` → matchea cualquier tipo/canal
  - fila `scope=type, target=birthday` → matchea solo ese tipo
  - fila `scope=channel, target=email` → matchea solo ese canal
  - múltiples filas (global + type) → retorna alguna (LIMIT 1)
  - recipient con casing distinto → matchea por canonical
