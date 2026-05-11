# ADL-005: FOR UPDATE SKIP LOCKED para reclamación concurrente de jobs

**Fecha**: 2026-05-11
**Estado**: Aceptado
**Feature**: 002-email-dispatch (Worker / dispatch_queue)

## Contexto

Múltiples instancias de `Worker` pueden ejecutarse en paralelo (threads, procesos, contenedores). Sin coordinación, dos workers pueden reclamar el mismo job y despacharlo dos veces, generando duplicados en el proveedor.

## Decisión

Usar `SELECT ... FOR UPDATE SKIP LOCKED` en la query de reclamación:

```sql
SELECT id FROM dispatch_queue
WHERE status = 'pending' AND next_attempt_at <= CLOCK_TIMESTAMP()
ORDER BY next_attempt_at ASC
LIMIT $1
FOR UPDATE SKIP LOCKED
```

- **`FOR UPDATE`**: adquiere un lock de fila exclusivo al momento de la lectura.
- **`SKIP LOCKED`**: omite filas que otro worker ya tiene bloqueadas en lugar de bloquearse o fallar.
- El UPDATE a `in_flight` ocurre en la misma transacción, atómicamente con el lock.

Verificado con el spec `:threads` (`concurrent workers claim disjoint sets of jobs`): 2 threads con `batch_size: 1` procesan 2 jobs distintos sin solapamiento.

## Alternativas consideradas

| Alternativa | Problema |
|---|---|
| `SELECT ... FOR UPDATE` sin SKIP | Workers se bloquean entre sí (throughput secuencial) |
| Optimistic locking con `lock_version` | Requiere loop de retry en la aplicación; más lógica, peor throughput |
| Redis/Sidekiq como broker | Introduce dependencia de infraestructura nueva fuera del scope del challenge |
| Estado `claimed_by` en la tabla | No garantiza exclusión a nivel DB; race condition posible entre SELECT y UPDATE |

## Consecuencias

- El Worker puede escalar horizontalmente sin coordinación externa.
- Jobs nunca se despachan dos veces simultáneamente (garantía a nivel PostgreSQL).
- `SKIP LOCKED` requiere PostgreSQL ≥ 9.5; compatible con PG 17 del stack.
- Relacionado con ADL-004: dentro de la misma query se usa `CLOCK_TIMESTAMP()` para evitar el problema de transacción DatabaseCleaner.

## Extensión 2026-05-11 — webhook_events (feature 003-audit-query)

El mismo patrón se reusa para reclamar jobs de `webhook_events` en `WebhookEventWorker.process_batch`. La query selecciona filas `WHERE status = 'pending'`, marca `processing` con `attempts = attempts + 1` y aplica `FOR UPDATE SKIP LOCKED` para soportar múltiples workers simultáneos sin doble procesamiento. La única diferencia con `DispatchQueue` es que no usa backoff exponencial: si el procesador falla, el job se marca `failed` con `failed_reason` (la verificación de firma ocurre antes de persistir, así que las fallas reales son raras y suelen requerir intervención manual).
