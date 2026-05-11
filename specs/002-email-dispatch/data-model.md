# Data Model — 002-email-dispatch

**Fecha**: 2026-05-10

---

## Tablas nuevas en esta fase

### `dispatch_queue`

Cola de despacho (Capa C del pipeline). Un job por evento creado.

```sql
CREATE TABLE dispatch_queue (
  id              BIGSERIAL PRIMARY KEY,
  event_id        BIGINT      NOT NULL,  -- sin FK declarativa; ver ADL-005
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
- `event_id` no tiene FK declarativa — `notification_events` es particionada con PK compuesta
  `(id, idempotency_window_ts)` y Postgres no acepta FK a columnas que no sean PK/UNIQUE completa.
  La integridad se garantiza por `EventBuilder#persist` que hace el enqueue en la misma transacción.
  Ver **ADL-005**.
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
  # Sin belongs_to :notification_event — no hay FK declarativa (ver ADL-005)

  BACKOFF_SCHEDULE = [ 1.minute, 5.minutes, 25.minutes ].freeze
  MAX_ATTEMPTS     = BACKOFF_SCHEDULE.size

  validates :event_id,        presence: true
  validates :priority,        inclusion: { in: %w[critical standard bulk] }
  validates :status,          inclusion: { in: %w[pending in_flight done failed] }
  validates :attempts,        numericality: { greater_than_or_equal_to: 0 }
  validates :next_attempt_at, presence: true

  def next_backoff
    BACKOFF_SCHEDULE[attempts] || BACKOFF_SCHEDULE.last
  end

  def permanent_failure?
    attempts >= MAX_ATTEMPTS
  end
end

# app/central/audit/notification_audit.rb
class NotificationAudit < ApplicationRecord
  validates :correlation_id, presence: true
  validates :status,         presence: true
end
```

---

## Factory (FactoryBot)

```ruby
FactoryBot.define do
  factory :dispatch_queue do
    event_id        { 1 }   # referencia simple, sin asociación AR (ver ADL-005)
    priority        { 'standard' }
    status          { 'pending' }
    attempts        { 0 }
    next_attempt_at { Time.current }

    trait :in_flight do
      status    { 'in_flight' }
      locked_at { Time.current }
    end

    trait :failed do
      status        { 'failed' }
      attempts      { DispatchQueue::MAX_ATTEMPTS }
      failed_reason { 'sendgrid_5xx: 503' }
    end

    trait :done do
      status   { 'done' }
      attempts { 1 }
    end
  end

  factory :notification_audit do
    correlation_id { SecureRandom.uuid }
    status         { 'enqueued' }
    channel        { 'email' }

    trait :dispatched do status { 'dispatched' } end
    trait :delivered  do status { 'delivered'  } end
    trait :failed     do status { 'failed'     } end
  end
end
```
