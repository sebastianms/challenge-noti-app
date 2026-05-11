# Data Model — 003-audit-query

## Cambios al esquema existente

### `notification_audit` — agregar 2 columnas

```sql
ALTER TABLE notification_audit
  ADD COLUMN recipient_canonical TEXT,
  ADD COLUMN source TEXT NOT NULL DEFAULT 'internal'
    CHECK (source IN ('internal', 'sendgrid_webhook'));

CREATE INDEX ON notification_audit (recipient_canonical)
  WHERE recipient_canonical IS NOT NULL;

CREATE INDEX ON notification_audit (status, created_at);
```

### Notas

- `recipient_canonical` es NULLable. Filas creadas antes de la migración tienen NULL (sin backfill, ver `research.md` R2).
- `source` con default `internal` para no romper inserts existentes; al agregar el procesador de webhooks, el código setea `sendgrid_webhook` explícitamente.
- El índice parcial sobre `recipient_canonical` evita indexar NULLs, reduce tamaño y acelera US2.
- El índice compuesto `(status, created_at)` cubre filtros como "failed entre el día X y Y" sin escanear toda la partición.

## Tabla nueva: `webhook_events`

```sql
CREATE TABLE webhook_events (
  id              BIGSERIAL PRIMARY KEY,
  source          TEXT NOT NULL DEFAULT 'sendgrid',
  payload         JSONB NOT NULL,
  signature       TEXT NOT NULL,
  signature_ts    TEXT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'processing', 'processed', 'failed')),
  received_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  locked_at       TIMESTAMPTZ,
  processed_at    TIMESTAMPTZ,
  failed_reason   TEXT,
  attempts        INT NOT NULL DEFAULT 0
);

CREATE INDEX ON webhook_events (status, received_at)
  WHERE status IN ('pending', 'processing');
```

### Notas

- Tabla **no particionada**: volumen esperado bajo (~bounce rate × envíos), no requiere partitioning.
- `payload` guarda el array crudo recibido del webhook completo (no por evento individual).
- `signature` y `signature_ts` se persisten para auditoría — en caso de disputa de seguridad, podemos re-verificar.
- Índice parcial sobre estados activos evita escanear las filas ya procesadas, idéntico patrón a `dispatch_queue`.

## Validaciones AR

### `NotificationAudit`

```ruby
validates :correlation_id, presence: true
validates :status,         presence: true
validates :source, inclusion: { in: %w[internal sendgrid_webhook] }
```

### `WebhookEvent`

```ruby
validates :payload,      presence: true
validates :signature,    presence: true
validates :signature_ts, presence: true
validates :status, inclusion: { in: %w[pending processing processed failed] }
```

## Flujo de datos

```text
SendGrid → POST /webhooks/sendgrid
         ↓
         SendgridSignature.verify (Ed25519)
         ↓
         WebhookEvent.create(status: "pending", payload: raw_array, signature, signature_ts)
         ↓ 200 OK al cliente
         ↓
         WebhookEventWorker.process_batch (loop SKIP LOCKED)
         ↓
         SendgridEventProcessor.process(webhook_event)
         ↓ por cada evento en payload:
         NotificationAudit.create(
           correlation_id: event["custom_args"]["correlation_id"],
           status:         translate(event["event"]),  # delivered/bounced/spam
           channel:        "email",
           source:         "sendgrid_webhook",
           recipient_canonical: event["email"]&.downcase,
           payload:        event,
           metadata:       { sg_timestamp: event["timestamp"], type: event["type"] }
         )
         ↓
         WebhookEvent.update(status: "processed", processed_at: now)
```

## Mapeo de eventos SendGrid → status interno

| SendGrid event | status persistido |
|---|---|
| `delivered` | `delivered` |
| `bounce` | `bounced` |
| `spamreport` | `spam_reported` |
| `dropped` | `dropped` |
| `deferred` | `deferred` |
| `open`, `click`, otros | se persisten igual con su nombre directo (sin sufijo) |

> El campo `source = sendgrid_webhook` es lo que distingue del `delivered` interno generado por el Worker tras un 202 de la API.
