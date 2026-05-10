# ADL-001 — Partition key de `notification_events`: `idempotency_window_ts` en vez de `created_at`

**Status**: Accepted
**Date**: 2026-05-10
**Feature**: `001-foundational-api`
**Authors**: Sebastián Machuca

## Contexto

La tabla `notification_events` necesita una `UNIQUE constraint` sobre `idempotency_hash` para garantizar que dos invocaciones equivalentes a `FooNotification.send(...)` produzcan exactamente una fila. Esto es la implementación de R4 (idempotencia, 0% duplicados accidentales) en `mission.md`.

La tabla también necesita ser **particionada por rango de tiempo** desde el día 1, porque a 500.000 inserts/hora la migración futura a tabla particionada exigiría downtime no trivial.

En PostgreSQL, una `UNIQUE constraint` sobre una tabla particionada **debe incluir todas las columnas de la clave de partición**. Esta regla es la que fuerza la decisión.

### Problema con la primera propuesta (`PARTITION BY created_at`)

La propuesta original del documento `MiniCentral De Notificaciones.md` y la primera versión del `data-model.md` usaban:

```sql
PARTITION BY RANGE (created_at)
UNIQUE (idempotency_hash, created_at)
```

Esto **no funciona** para garantizar idempotencia: `created_at` se setea con `now()` en cada INSERT y dos invocaciones equivalentes a 100 ms de distancia tienen `created_at` distintos al microsegundo. La UNIQUE permitiría ambas filas, rompiendo R4.

Detectado durante la redacción del contrato del `EventBuilder` en Phase 3 (Plan).

## Decisión

Particionar `notification_events` por **`idempotency_window_ts`** (timestamp del inicio de la ventana truncada en UTC), e incluir esa columna en la UNIQUE constraint.

```sql
CREATE TABLE notification_events (
  ...
  idempotency_hash       TEXT        NOT NULL,
  idempotency_window_ts  TIMESTAMPTZ NOT NULL,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (id, idempotency_window_ts),
  UNIQUE (idempotency_hash, idempotency_window_ts)
) PARTITION BY RANGE (idempotency_window_ts);
```

**Razonamiento**: dos invocaciones equivalentes (mismo `recipient`, `type`, `context_id` dentro de la misma ventana) tienen el mismo `window_ts` por construcción. Por tanto:
- Caen siempre en la misma partición.
- La constraint `UNIQUE (idempotency_hash, idempotency_window_ts)` rechaza la segunda con `ON CONFLICT DO NOTHING`.
- `created_at` queda como columna informativa (timestamp real de inserción), sin participar en unicidad ni partición.

## Consecuencias

### Positivas

- **R4 cumplido correctamente**: la garantía "0% duplicados accidentales" es real, no solo declarada.
- **Atomicidad gratuita**: un solo `INSERT ... ON CONFLICT DO NOTHING` resuelve la unicidad sin lookups previos ni locks distribuidos.
- **Particionamiento correcto desde día 1**: sin migración futura ni downtime esperado.
- **Particiones se pueden dropear con seguridad**: cada partición agrupa eventos cuyo `window_ts` cae en su rango; al expirar la retención, `DROP TABLE` es metadata-only.

### Negativas / a mitigar

- **Las consultas de auditoría desde la UI deben filtrar por `idempotency_window_ts`** para activar partition pruning. Si la UI permite filtrar por `created_at` (más natural para el usuario), el optimizador escaneará todas las particiones a menos que ambos timestamps se usen juntos.
  - **Mitigación**: la feature `004-audit` debe documentar que los queries de auditoría incluyan ambos rangos, o desnormalizar `window_ts` desde la UI ("últimas 24h" → `[floor(now-24h, 1min), floor(now, 1min)]`).
- **`created_at` ya no es la clave temporal "natural"**: a futuro, lectores del schema podrían sorprenderse de que la PK incluya `window_ts` y no `created_at`. Mitigación: comentario en la migración explicando el motivo, y este ADL referenciado.
- **`window_ts` y `created_at` pueden divergir** si el reloj del nodo está desincronizado. Diferencias de segundos no rompen nada (ambas siguen estando en la misma partición mensual). Diferencias de minutos podrían poner una invocación en la "partición incorrecta". Asumido cubierto por NTP del cluster.

### Neutras

- Una consulta del estilo "cuántos eventos se crearon entre las 10:00 y las 11:00" puede usar `created_at` en el WHERE pero **no** se beneficia de partition pruning. Para análisis de volumen por hora, se recomienda usar `idempotency_window_ts` (que está dentro del mismo minuto que `created_at` para todos los efectos prácticos).

## Alternativas consideradas

### A. `PARTITION BY created_at` + `UNIQUE (idempotency_hash, created_at)` (propuesta original)
**Rechazada**: rompe R4. Dos invocaciones a microsegundos de distancia generan dos filas.

### B. `PARTITION BY created_at` + `UNIQUE (idempotency_hash)` global (no particionada)
**Rechazada**: PostgreSQL no permite índices únicos globales sobre tablas particionadas (a partir de PG 11 los UNIQUE deben incluir la partition key). La única forma de tener unicidad global sería una **segunda tabla** `notification_event_keys` no particionada usada solo para deduplicar — agrega complejidad y un punto de contención adicional sin beneficio claro.

### C. Tabla plana, particionar después
**Rechazada**: la migración futura de tabla plana a particionada con 360M+ filas exige downtime considerable. Hacerlo desde el día 1 es trivial.

### D. Particionar por `(date_trunc('day', created_at))` con columna generada
**Rechazada**: mismo problema que A — la columna generada se deriva de `created_at`, que sigue variando en microsegundos.

## Referencias

- `specs/001-foundational-api/data-model.md` — DDL definitivo.
- `specs/001-foundational-api/contracts/event_builder.rb` — uso de `ON CONFLICT (idempotency_hash, idempotency_window_ts)`.
- `specs/001-foundational-api/research.md` R-01 — justificación general de UNIQUE + ON CONFLICT.
- PostgreSQL docs: [Table Partitioning — Limitations of Declarative Partitioning](https://www.postgresql.org/docs/16/ddl-partitioning.html#DDL-PARTITIONING-DECLARATIVE-LIMITATIONS).
