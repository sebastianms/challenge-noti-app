# Contract — Extensión de `WebhookEventWorker` para auto-blacklist

## Comportamiento por tipo de evento

| event de SendGrid | Acción de audit | Acción de blacklist |
|-------------------|------------------|---------------------|
| `delivered`       | INSERT audit `delivered` | — |
| `bounce` (type=bounce, hard) | INSERT audit `bounced` | INSERT blacklist `source=hard_bounce` (ON CONFLICT DO NOTHING) |
| `bounce` (type=blocked, soft) | INSERT audit `bounced` | — |
| `dropped`         | INSERT audit `dropped` | INSERT blacklist `source=dropped` (ON CONFLICT DO NOTHING) |
| `spamreport`      | INSERT audit `spamreport` | INSERT blacklist `source=spamreport` (ON CONFLICT DO NOTHING) |
| `deferred`        | INSERT audit `deferred` | — |

## Forma del INSERT de blacklist

```sql
INSERT INTO notification_blacklist
  (recipient_canonical, scope, target, source, reason, created_at)
VALUES
  ($1, 'channel', 'email', $2, $3, CLOCK_TIMESTAMP())
ON CONFLICT (recipient_canonical, scope, target) DO NOTHING;
```

`reason` se compone de: `"#{event['reason']} (sg_event_id=#{event['sg_event_id']})"` si está disponible. Permite trazabilidad cruzada con dashboard de SendGrid.

## Transaccionalidad

Audit + blacklist en **una sola transacción** por evento. Si la blacklist falla, el audit también roll-backea — el evento queda en `webhook_events.status='processing'` y se reintenta.

```ruby
ActiveRecord::Base.transaction do
  NotificationAudit.insert!(...)
  NotificationBlacklist.insert_on_conflict_do_nothing(...) if hard_failure?(event)
end
```

## Determinación de "hard"

```ruby
def self.hard_failure?(event)
  case event["event"]
  when "dropped", "spamreport" then true
  when "bounce" then event["type"] == "bounce"  # SendGrid: "bounce" = hard, "blocked" = soft
  else false
  end
end
```

## Tests requeridos

- `webhook_event_worker_blacklist_spec.rb`:
  - evento `bounce` con `type=bounce` → crea blacklist
  - evento `bounce` con `type=blocked` → NO crea blacklist
  - evento `dropped` → crea blacklist con `source=dropped`
  - evento `spamreport` → crea blacklist con `source=spamreport`
  - evento `deferred` → NO crea blacklist
  - evento repetido (mismo recipient, ya bloqueado) → idempotente, 1 sola fila
  - audit y blacklist en misma transacción (forzar fallo en blacklist → audit roll-backea)
