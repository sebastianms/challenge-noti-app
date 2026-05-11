# ADL-003 — FK declarativa omitida entre `dispatch_queue` y `notification_events`

**Status**: Accepted
**Date**: 2026-05-10
**Feature**: `002-email-dispatch`
**Authors**: Sebastián Machuca

## Contexto

`dispatch_queue` necesita referenciar el evento que originó el job de despacho. El diseño
inicial del `data-model.md` declaraba:

```sql
event_id BIGINT NOT NULL REFERENCES notification_events(id)
```

Al ejecutar la migración, PostgreSQL devolvió:

```
PG::InvalidForeignKey: ERROR: there is no unique constraint matching given keys
for referenced table "notification_events"
```

## Causa raíz

`notification_events` es una tabla particionada (`PARTITION BY RANGE (idempotency_window_ts)`).
En PostgreSQL, una **foreign key solo puede referenciar una tabla particionada si las columnas
referenciadas forman una constraint `UNIQUE` o `PRIMARY KEY` que incluya la partition key**.

La PK de `notification_events` es `(id, idempotency_window_ts)` — obligatorio porque en tablas
particionadas la uniqueness se aplica dentro de cada partición y la pk debe incluir la clave de
partición (ver ADL-001). Por tanto:

- `REFERENCES notification_events(id)` → **inválido**: `id` solo no es PK ni tiene UNIQUE
- `REFERENCES notification_events(id, idempotency_window_ts)` → **válido** pero implicaría que
  `dispatch_queue` almacene `idempotency_window_ts` también, acoplando innecesariamente la cola
  al esquema de particionamiento de los eventos.

## Decisión

Eliminar la FK declarativa. `event_id` se declara como `BIGINT NOT NULL` sin cláusula
`REFERENCES`:

```sql
event_id BIGINT NOT NULL
```

La integridad referencial se garantiza a nivel de aplicación: `Enqueuer.enqueue` se llama
**dentro del mismo bloque `ActiveRecord::Base.transaction`** que el INSERT en
`notification_events` (ver `EventBuilder#persist`). Si el INSERT del evento falla, el enqueue
no ocurre; si el enqueue falla, la transacción entera hace rollback.

## Consecuencias

### Positivas

- Migración ejecuta sin error.
- `dispatch_queue` no depende del esquema de particionamiento de `notification_events`.
  Si en el futuro cambia la clave de partición de eventos, `dispatch_queue` no requiere cambios.
- Sin overhead de FK check en cada INSERT (mínimo, pero real bajo carga).

### Negativas / a mitigar

- **No hay integridad referencial declarativa en la DB**: un `event_id` huérfano
  (evento eliminado sin limpiar la cola) no es detectado por Postgres.
  - **Mitigación**: el pipeline actual no elimina eventos; la retención es por expiración de
    particiones completas. Si se agrega lógica de borrado de eventos en el futuro, debe incluir
    limpieza de `dispatch_queue`.
- **`belongs_to :notification_event` en el modelo AR no funciona** sin la FK — el modelo
  `DispatchQueue` usa `event_id` como columna de referencia simple, sin asociación AR declarada.

### Neutras

- La restricción `NOT NULL` sobre `event_id` sí es declarativa y se mantiene.
- Los tests de integración verifican la coherencia event_id → dispatch_queue implícitamente
  al crear ambos en el mismo flujo.

## Alternativas consideradas

### A. FK a `(id, idempotency_window_ts)` en `dispatch_queue`

```sql
event_id            BIGINT      NOT NULL,
event_window_ts     TIMESTAMPTZ NOT NULL,
FOREIGN KEY (event_id, event_window_ts) REFERENCES notification_events(id, idempotency_window_ts)
```

**Rechazada**: acopla `dispatch_queue` al esquema de particionamiento de `notification_events`.
Cualquier cambio en la clave de partición de eventos exige migrar también la cola. Más columnas,
más complejidad, sin beneficio operativo real dado el patrón transaccional que ya garantiza coherencia.

### B. Tabla `notification_events` no particionada para recibir FK

**Rechazada**: contradice ADL-001 y ADL-002. La tabla debe estar particionada desde el inicio
por volumen y retención.

### C. Tabla intermedia de unicidad (non-partitioned) solo para FK target

**Rechazada**: agrega un punto de contención y complejidad sin justificación. La integridad
transaccional del `EventBuilder` es suficiente.

## Referencias

- ADL-001 — Partition key de `notification_events`: explica por qué la PK es compuesta.
- `specs/002-email-dispatch/data-model.md` — DDL actualizado sin FK.
- `app/central/broker/enqueuer.rb` — implementación del enqueue transaccional (Phase US1).
- PostgreSQL docs: [Declarative Partitioning — Limitations](https://www.postgresql.org/docs/current/ddl-partitioning.html#DDL-PARTITIONING-DECLARATIVE-LIMITATIONS)
