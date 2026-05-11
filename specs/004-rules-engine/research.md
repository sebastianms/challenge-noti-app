# Research — 004-rules-engine

## R1 — Cache store

**Decisión**: usar `Rails.cache` con TTL 5 min e invalidación explícita en `after_save`/`after_destroy` del modelo `NotificationRule`.

**Rationale**:
- `Rails.cache` ya está configurado (`:memory_store` en dev/test). Producción puede swappearse a `:mem_cache_store` o `:redis_cache_store` cambiando un config, sin tocar código.
- TTL de 5 min es el SLO declarado en spec (SC-001).
- La invalidación explícita previene esperar al TTL cuando el cambio es local; el TTL es la garantía si la invalidación falla o si hay múltiples procesos sin pub/sub.

**Alternativas consideradas**:
1. **Memoización a nivel proceso (Hash)**: descartada — no respeta TTL ni invalidación cross-process; con múltiples workers cada uno tendría una vista distinta.
2. **Consultar BD siempre + agregar prepared statement**: descartada — 100 envíos / sec × 1 lookup = 100 hits/s a una tabla raramente cambiada. Cache es la solución obvia.
3. **Redis directo (sin `Rails.cache`)**: descartada — agrega dependencia de runtime; `Rails.cache` ya abstrae esto.

**Implementación**:
```ruby
RuleCache.fetch(notification_type) → Rails.cache.fetch("rule:#{type}", expires_in: 5.minutes) { NotificationRule.find_by(notification_type: type) }
RuleCache.invalidate(notification_type) → Rails.cache.delete("rule:#{type}")
```

---

## R2 — Snapshot de regla en `pending_digests`

**Decisión**: persistir un campo `rule_snapshot JSONB` en cada fila de `pending_digests` con la configuración relevante de la regla al momento del INSERT.

**Rationale**:
- FR-010 exige que items pendientes no se descarten si la regla se borra.
- Si la regla cambia mientras hay items en cola, el snapshot evita comportamiento inconsistente (ej. consolidar con un nuevo `digest_template` que el usuario no esperaba).
- JSONB es barato; las filas se consolidan en minutos, no semanas.

**Snapshot incluye**: `rule_id`, `notification_type`, `digest_window_seconds`, `channels`, `priority` al momento del insert. Suficiente para que el scheduler decida sin re-consultar.

**Alternativas**:
1. **FK + ON DELETE SET NULL**: descartada — al borrarse la regla, el item queda huérfano sin contexto de cómo procesarlo.
2. **FK + ON DELETE RESTRICT**: descartada — bloquea legítimas eliminaciones de reglas hasta vaciar la cola; mala UX.

---

## R3 — Rate limit query

**Decisión**: contar filas en `notification_audit` con un índice cubriente sobre `(notification_type, recipient_canonical, created_at)`.

**Rationale**:
- `notification_audit` ya es la source of truth de envíos (Phase 3).
- Particionado mensual: una query con `created_at >= now - 24h` solo escanea la partición actual (~máximo 2 si cruza fin de mes).
- Índice compuesto sirve para el lookup exacto. Estimado: < 5 ms para tablas de ~1M filas por partición.

**Query**:
```sql
SELECT COUNT(*) FROM notification_audit
WHERE notification_type = $1
  AND recipient_canonical = $2
  AND status IN ('dispatched','delivered')
  AND created_at >= NOW() - INTERVAL '24 hours'
```

**Nota**: `notification_audit` actualmente NO tiene columna `notification_type`. Hay que agregarla. Ver `data-model.md` migración 20260512000003.

**Alternativas**:
1. **Tabla contador agregada**: rechazada — duplica fuente de verdad, sujeta a drift (audit insert ok pero contador failed).
2. **Window function con DENSE_RANK**: rechazada — más compleja, mismo costo.

---

## R4 — Worker concurrency: SKIP LOCKED

**Decisión**: `DigestScheduler` reusa el patrón de ADL-005. Query:

```sql
UPDATE pending_digests
SET status = 'consolidating', locked_at = CLOCK_TIMESTAMP()
WHERE id IN (
  SELECT id FROM pending_digests
  WHERE status = 'pending' AND dispatch_at <= CLOCK_TIMESTAMP()
  ORDER BY dispatch_at ASC
  LIMIT $1
  FOR UPDATE SKIP LOCKED
)
RETURNING id, notification_type, recipient_canonical
```

Luego en Ruby agrupa por `(notification_type, recipient_canonical)`, crea fila en `dispatch_queue`, y un `UPDATE ... SET status='consolidated', consolidated_into=$correlation_id` sobre los IDs reclamados.

**ADL extensión**: ADL-005 ya menciona webhook_events; agregar nota sobre pending_digests en la fase Polish.

---

## R5 — Acoplamiento con EventBuilder existente

**Decisión**: `EventBuilder` ahora invoca `RulesEngine.decide(event:)` en lugar de `Enqueuer.enqueue` directo. Según el `Decision`:

- `:dispatch` → `Enqueuer.enqueue(event_id:, correlation_id:, recipient_canonical:, priority: rule.priority || @priority)`.
- `:digest` → `PendingDigest.create!(...)` con snapshot.
- `:filter` → `NotificationAudit.create!(status: "filtered", metadata: {reason:, rule_id:})`.

**Compatibilidad hacia atrás**: si `RulesEngine` retorna `:dispatch` por falta de regla (FR-001), el comportamiento es idéntico a Phase 3. Los specs existentes deben seguir verdes sin cambios.

**Riesgo**: regresión silenciosa si EventBuilder pierde el branching. Mitigado con el spec de integración `spec/integration/rules_pipeline_spec.rb`.

---

## R6 — Priority en regla vs en `send(priority:)`

**Decisión**: precedencia regla > argumento. Si la regla define `priority`, ese valor se pasa a `Enqueuer.enqueue`. Si no, se respeta el `priority:` del llamante (default `:standard`).

**Rationale**: producto configura prioridad sin tocar código de notificaciones. Si quieren forzar prioridad por código, omiten el campo en la regla.

---

## R7 — Channels array vacío vs null

**Decisión**:
- `channels = NULL` → no restringe (compatible con notificaciones sin regla).
- `channels = []` (array vacío) → bloqueo explícito, audit con `reason=disabled`.
- `channels = ['email']` → permite solo email (en Phase 5 solo hay email; futuro: si llega SMS se filtra).

**Rationale**: distinguir "no configurado" de "explícitamente sin canales" evita ambigüedad. Postgres soporta ambos con `text[]`.
