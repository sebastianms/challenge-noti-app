# Data Model — 001-foundational-api

**Date**: 2026-05-10

## Entidades

### `NotificationEvent`

Registro durable de cada invocación a `send` que pasa la validación de input y la deduplicación.

| Campo | Tipo | Constraints | Descripción |
| :---- | :---- | :---- | :---- |
| `id` | `BIGSERIAL` | PK (compuesta con `created_at`) | Identificador interno; incremental por partición. |
| `notification_type` | `TEXT` | NOT NULL | Identificador estable del tipo (declarado o derivado del FQN). |
| `recipient_canonical` | `TEXT` | NOT NULL | Forma canónica del destinatario (lowercase + trim para email; tal cual para user_id). |
| `recipient_type` | `TEXT` | NOT NULL, CHECK IN (`email`, `user_id`) | Cómo se interpretará en el dispatch posterior. |
| `context_id` | `TEXT` | NULL | Identificador del objeto del contexto (ej. `invoice_id=42`). NULL si no se pasó. |
| `payload` | `JSONB` | NOT NULL DEFAULT `'{}'::jsonb` | Datos arbitrarios del integrador (contexto serializado). |
| `idempotency_hash` | `TEXT` | NOT NULL | SHA256 hex de `(type, recipient_canonical, context_id_or_no_context, window_ts)`. |
| `idempotency_window_ts` | `TIMESTAMPTZ` | NOT NULL | Inicio de la ventana truncada (UTC). Útil para auditoría/debugging. |
| `correlation_id` | `UUID` | NOT NULL DEFAULT `gen_random_uuid()` UNIQUE | Identificador trazable expuesto al integrador y a soporte. |
| `created_at` | `TIMESTAMPTZ` | NOT NULL DEFAULT `now()` | Timestamp real de creación. **Clave de partición.** |

**Reglas de validación**:

- `recipient_canonical` no puede estar vacío ni exceder 320 caracteres (límite RFC 5321 para emails; user_ids razonables encajan cómodamente).
- `notification_type` es un slug snake_case (`/^[a-z0-9_/]+$/`).
- `payload` debe ser serializable a JSON; floats infinitos / NaN / claves no-string lanzan error temprano.
- `context_id` se normaliza a string; si el integrador pasa un entero, se convierte (`42 → "42"`).
- `idempotency_hash` es siempre 64 caracteres hex (SHA256).

**Cardinalidad esperada**:

- 500.000 inserts/hora pico → ~12M filas/día → ~360M filas/mes.
- Particionamiento mensual: cada partición ~360M filas, índices ~10-15 GB. Manejable con read replica para queries de auditoría.

## DDL

```sql
-- Tabla padre particionada por mes
CREATE TABLE notification_events (
  id                       BIGSERIAL,
  notification_type        TEXT       NOT NULL,
  recipient_canonical      TEXT       NOT NULL,
  recipient_type           TEXT       NOT NULL,
  context_id               TEXT,
  payload                  JSONB      NOT NULL DEFAULT '{}'::jsonb,
  idempotency_hash         TEXT       NOT NULL,
  idempotency_window_ts    TIMESTAMPTZ NOT NULL,
  correlation_id           UUID       NOT NULL DEFAULT gen_random_uuid(),
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),

  PRIMARY KEY (id, idempotency_window_ts),
  UNIQUE (idempotency_hash, idempotency_window_ts),
  UNIQUE (correlation_id, idempotency_window_ts),

  CONSTRAINT recipient_type_valid    CHECK (recipient_type IN ('email','user_id')),
  CONSTRAINT recipient_not_empty     CHECK (length(recipient_canonical) > 0),
  CONSTRAINT recipient_max_length    CHECK (length(recipient_canonical) <= 320),
  CONSTRAINT idempotency_hash_format CHECK (idempotency_hash ~ '^[a-f0-9]{64}$'),
  CONSTRAINT notification_type_slug  CHECK (notification_type ~ '^[a-z0-9_/]+$')
) PARTITION BY RANGE (idempotency_window_ts);

-- Particiones iniciales
CREATE TABLE notification_events_2026_05 PARTITION OF notification_events
  FOR VALUES FROM (TIMESTAMP '2026-05-01' AT TIME ZONE 'UTC') TO (TIMESTAMP '2026-06-01' AT TIME ZONE 'UTC');
CREATE TABLE notification_events_2026_06 PARTITION OF notification_events
  FOR VALUES FROM (TIMESTAMP '2026-06-01' AT TIME ZONE 'UTC') TO (TIMESTAMP '2026-07-01' AT TIME ZONE 'UTC');

-- Índices auxiliares (creados en cada partición automáticamente)
CREATE INDEX idx_events_recipient ON notification_events (recipient_canonical, idempotency_window_ts);
CREATE INDEX idx_events_type      ON notification_events (notification_type, idempotency_window_ts);
CREATE INDEX idx_events_created   ON notification_events (created_at);
```

**Notas sobre las constraints UNIQUE y la elección de la clave de partición**:

- En tablas particionadas, los índices únicos **deben** incluir la clave de partición. Particionamos por **`idempotency_window_ts`** (no por `created_at`) porque dos invocaciones equivalentes tienen el mismo `window_ts` exacto pero `created_at` distintos (microsegundos). Si particionáramos por `created_at`, la constraint `UNIQUE (idempotency_hash, created_at)` permitiría duplicados a microsegundos de distancia.
- Con `idempotency_window_ts` como clave de partición, dos invocaciones con el mismo hash van garantizadamente a la misma partición, y `UNIQUE (idempotency_hash, idempotency_window_ts)` resuelve la unicidad correctamente.
- `created_at` queda como columna informativa (timestamp real de inserción) sin participar en unicidad ni partición.
- Lookups por `correlation_id` desde la UI usan el índice `UNIQUE (correlation_id, idempotency_window_ts)`. La UI siempre debe pasar un rango de `window_ts` (típicamente "últimas 24h") para activar partition pruning; sin él, el query escanea todas las particiones.

## Migración Rails

```ruby
# db/migrate/20260510000001_create_notification_events.rb
class CreateNotificationEvents < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE TABLE notification_events (
        id                       BIGSERIAL,
        notification_type        TEXT       NOT NULL,
        recipient_canonical      TEXT       NOT NULL,
        recipient_type           TEXT       NOT NULL,
        context_id               TEXT,
        payload                  JSONB      NOT NULL DEFAULT '{}'::jsonb,
        idempotency_hash         TEXT       NOT NULL,
        idempotency_window_ts    TIMESTAMPTZ NOT NULL,
        correlation_id           UUID       NOT NULL DEFAULT gen_random_uuid(),
        created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
        PRIMARY KEY (id, idempotency_window_ts),
        UNIQUE (idempotency_hash, idempotency_window_ts),
        UNIQUE (correlation_id, idempotency_window_ts),
        CONSTRAINT recipient_type_valid    CHECK (recipient_type IN ('email','user_id')),
        CONSTRAINT recipient_not_empty     CHECK (length(recipient_canonical) > 0),
        CONSTRAINT recipient_max_length    CHECK (length(recipient_canonical) <= 320),
        CONSTRAINT idempotency_hash_format CHECK (idempotency_hash ~ '^[a-f0-9]{64}$'),
        CONSTRAINT notification_type_slug  CHECK (notification_type ~ '^[a-z0-9_/]+$')
      ) PARTITION BY RANGE (idempotency_window_ts);
    SQL

    create_partition('2026-05-01', '2026-06-01')
    create_partition('2026-06-01', '2026-07-01')

    add_index :notification_events, [:recipient_canonical, :idempotency_window_ts]
    add_index :notification_events, [:notification_type, :idempotency_window_ts]
    add_index :notification_events, :created_at
  end

  def down
    drop_table :notification_events
  end

  private

  def create_partition(from, to)
    name = "notification_events_#{Date.parse(from).strftime('%Y_%m')}"
    execute <<~SQL
      CREATE TABLE #{name} PARTITION OF notification_events
      FOR VALUES FROM ('#{from}') TO ('#{to}');
    SQL
  end
end
```

**Mantenimiento de particiones**: queda fuera del alcance de esta feature. Se implementará un job programado en una feature posterior (`PartitionManager`) que crea la partición del mes siguiente y opcionalmente dropea las muy viejas (retención TBD por compliance).

## Modelo ActiveRecord

```ruby
# app/central/models/notification_event.rb
module Central
  class NotificationEvent < ApplicationRecord
    self.table_name = "notification_events"

    # No hay validaciones de modelo: el motor (CHECKs + UNIQUE) es la única
    # fuente de verdad para evitar drift entre Ruby y Postgres a 140 rps.
    # Las validaciones de input ocurren ANTES de llegar acá, en EventBuilder.
  end
end
```

## Out of scope

- Tablas `dispatch_queue`, `notification_audit`, `notification_rules`, `notification_blacklist`, `notification_templates`, `pending_digests`. Cada una pertenece a su propia feature.
- Job de mantenimiento de particiones.
- Backfill / seed de eventos históricos.
