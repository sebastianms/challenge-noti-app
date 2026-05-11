# Research — 002-email-dispatch

**Fecha**: 2026-05-10

---

## RQ-01: HTTP Stubbing — WebMock vs VCR

**Pregunta**: ¿Usar solo WebMock o WebMock + cassettes VCR para los tests del `SendgridAdapter`?

**Decisión**: **WebMock puro** con stubs declarados en los specs.

**Rationale**:
- Los cassettes VCR capturan respuestas reales → necesitan una API key real para la primera grabación.
- WebMock permite definir el contrato HTTP esperado directamente en el spec, más legible y sin archivos externos.
- El adapter es simple (un POST a `/v3/mail/send`); la complejidad de VCR no aporta valor aquí.
- La suite de Phase 1 ya usa `allow(Rails).to receive(:logger)` — el patrón de stub en RSpec es familiar.

**Alternativa rechazada**: VCR con cassettes — requiere API key para grabar y añade archivos que hay que mantener versionados.

**Gemas a agregar**: `webmock` (~> 3.0) en grupo `:test`.

---

## RQ-02: Sendgrid API v3 — Contrato HTTP mínimo

**Endpoint**: `POST https://api.sendgrid.com/v3/mail/send`

**Headers requeridos**:
```
Authorization: Bearer {SENDGRID_API_KEY}
Content-Type: application/json
X-Correlation-ID: {uuid}
```

**Body mínimo**:
```json
{
  "personalizations": [
    { "to": [{ "email": "recipient@example.com" }] }
  ],
  "from": { "email": "notifications@company.com" },
  "subject": "Título de la notificación",
  "content": [
    { "type": "text/html", "value": "<p>Cuerpo de la notificación</p>" }
  ]
}
```

**Respuestas**:
- `202 Accepted` — Sendgrid aceptó el mensaje (no significa entregado).
- `400 Bad Request` — payload inválido → error permanente, va directo a DLQ.
- `429 Too Many Requests` — throttling → reintentable con backoff.
- `5xx` — error transitorio → reintentable con backoff.

**Clasificación de errores**:
- **Permanentes** (no reintentar): 4xx excepto 429.
- **Transitorios** (reintentar con backoff): 429, 5xx, timeout.

**From address**: configurable via `SENDGRID_FROM_EMAIL` env var; default `notifications@company.com` en dev.

---

## RQ-03: Particionamiento de `notification_audit` por día

**Decisión**: usar `PARTITION BY RANGE (created_at)` con particiones mensuales (no diarias) en Phase 3; Phase 4 puede añadir particiones diarias si el volumen lo justifica.

**Rationale**: con 140 rps y auditoría de todas las transiciones (~3-5 por envío), se generan ~60 M filas/mes. Una partición mensual es manejable con DROP TABLE mensual; partición diaria es necesaria solo si hay consultas ad-hoc por día que necesiten partition pruning. Phase 4 implementará el `PartitionManager` que puede ajustar la granularidad.

**Corrección respecto a la spec**: la spec dice "particionada por día" pero mensual es más pragmático para Phase 3. Se documenta aquí para alinear con el implementador.

---

## RQ-04: `dispatch_queue` — índice SKIP LOCKED eficiente

**Consulta del Worker**:
```sql
SELECT * FROM dispatch_queue
WHERE status = 'pending'
  AND next_attempt_at <= NOW()
ORDER BY priority_order, next_attempt_at
FOR UPDATE SKIP LOCKED
LIMIT 10;
```

**Índice requerido**:
```sql
CREATE INDEX idx_dispatch_queue_workable
  ON dispatch_queue (status, next_attempt_at)
  WHERE status = 'pending';
```

**Orden de prioridad**: `critical → standard → bulk`. Implementado con un campo `priority_order INT` calculado en el INSERT (1, 2, 3) o con un `CASE` en el ORDER BY. El campo `priority` TEXT se mantiene legible; el orden se hace con `CASE WHEN priority = 'critical' THEN 1 ...`.

---

## RQ-05: Transacción atómica `notification_events` + `dispatch_queue`

**Patrón**:
```ruby
ActiveRecord::Base.transaction do
  event = NotificationEvent.create!(...)   # INSERT ON CONFLICT
  if event.persisted? && !duplicate?
    DispatchQueue.create!(event_id: event.id, ...)
  end
end
```

El `ON CONFLICT DO NOTHING` devuelve 0 filas afectadas cuando hay duplicado → `event.id` es nil → no se encola. Esto garantiza que duplicados no generan jobs.

**Nota**: en Rails 8 con `insert_all` el comportamiento de retorno de IDs es consistente con `returning: [:id]`. Se usará `NotificationEvent.insert(attrs, returning: [:id], unique_by: [:idempotency_hash, :idempotency_window_ts])` y se evaluará si el resultado está vacío.
