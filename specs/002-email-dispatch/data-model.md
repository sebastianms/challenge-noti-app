# Data Model — 002-email-dispatch

**Fecha**: 2026-05-10

---

## Tablas nuevas en esta fase

### `dispatch_queue`

Cola de despacho (Capa C del pipeline). Un job por evento creado.

```sql
CREATE TABLE dispatch_queue (
  id              BIGSERIAL PRIMARY KEY,
  event_id        BIGINT      NOT NULL REFERENCES notification_events(id),
  priority        TEXT        NOT NULL DEFAULT 'standard'
                              CHECK (priority IN ('critical', 'standard', 'bulk')),
  status          TEXT        NOT NULL DEFAULT 'pending'
                              CHECK (status IN ('pending', 'in_flight', 'done', 'failed')),
  attempts        INT         NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  locked_at       TIMESTAMPTZ,
  failed_reason   TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índice parcial para el SKIP LOCKED loop (solo filas accionables)
CREATE INDEX idx_dispatch_queue_workable
  ON dispatch_queue (next_attempt_at, priority)
  WHERE status = 'pending';
```

**Notas**:
- `attempts` empieza en 0 y se incrementa antes de cada intento.
- `locked_at` se setea cuando el Worker toma el job (`in_flight`); se limpia al completar o fallar.
- `failed_reason` documenta el motivo de DLQ: `"sendgrid_5xx"`, `"no_email_address"`, `"invalid_payload"`, etc.
- No se particiona en Phase 3 (tabla pequeña — jobs se resuelven rápido). Phase 10 puede evaluar.

---

### `notification_audit`

Log inmutable de transiciones de estado, particionado por mes.

```sql
CREATE TABLE notification_audit (
  id             BIGSERIAL,
  correlation_id UUID        NOT NULL,
  event_id       BIGINT,
  status         TEXT        NOT NULL,   -- enqueued | dispatched | delivered | failed | filtered
  channel        TEXT,                   -- 'email', 'sms', nil si es pre-despacho
  rule_snapshot  JSONB,
  payload        JSONB,
  metadata       JSONB,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

-- Partición inicial (mes actual)
CREATE TABLE notification_audit_2026_05
  PARTITION OF notification_audit
  FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');

-- Índices en la tabla padre (heredados por particiones)
CREATE INDEX ON notification_audit (correlation_id);
CREATE INDEX ON notification_audit USING GIN (payload);
CREATE INDEX ON notification_audit USING GIN (metadata);
```

**Estados registrados en Phase 3**:
| Estado | Cuándo | channel |
|--------|--------|---------|
| `enqueued` | Justo después del INSERT en `dispatch_queue` | nil |
| `dispatched` | Antes de llamar al adapter de Sendgrid | `'email'` |
| `delivered` | Después de respuesta 202 de Sendgrid | `'email'` |
| `failed` | Después de agotar reintentos (job → DLQ) | `'email'` |

---

## Tablas modificadas

### `notification_events` (existente)

No se cambia el DDL. Se agrega la asociación AR `has_one :dispatch_job, class_name: 'DispatchQueue'` para conveniencia en tests.

---

## Modelos ActiveRecord

```ruby
# app/central/broker/dispatch_queue.rb
class DispatchQueue < ApplicationRecord
  belongs_to :notification_event

  BACKOFF_SCHEDULE = [1.minute, 5.minutes, 25.minutes].freeze
  MAX_ATTEMPTS     = BACKOFF_SCHEDULE.size

  def next_backoff
    BACKOFF_SCHEDULE[attempts] || BACKOFF_SCHEDULE.last
  end

  def permanent_failure?
    attempts >= MAX_ATTEMPTS
  end
end

# app/central/audit/notification_audit.rb
class NotificationAudit < ApplicationRecord
  validates :correlation_id, :status, presence: true
end
```

---

## Factory (FactoryBot)

```ruby
FactoryBot.define do
  factory :dispatch_queue do
    association :notification_event
    priority        { 'standard' }
    status          { 'pending' }
    attempts        { 0 }
    next_attempt_at { Time.current }
  end

  factory :notification_audit do
    correlation_id { SecureRandom.uuid }
    status         { 'enqueued' }
    channel        { nil }
    payload        { {} }
    metadata       { {} }
  end
end
```
