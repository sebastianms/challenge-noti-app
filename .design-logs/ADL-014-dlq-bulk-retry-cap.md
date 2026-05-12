# ADL-014 — DLQ Bulk Retry: Cap 500 + Transaccionalidad (Phase 9)

**Fecha**: 2026-05-12
**Estado**: Aceptado
**Feature**: [008-admin-templates-dlq](../specs/008-admin-templates-dlq/)

---

## Contexto

La DLQ del sistema es `dispatch_queue WHERE status='failed'`. Tras un outage de SendGrid, pueden acumularse cientos o miles de jobs en este estado. Operaciones necesita evacuar la DLQ masivamente desde la UI sin consola Rails. Se debe evitar:

1. Inundar `dispatch_queue` con jobs repentinamente `pending` que saturen al Worker.
2. Race conditions con el Worker que procesa `pending` jobs con `FOR UPDATE SKIP LOCKED`.
3. Un audit entry por cada job reintentado (ruido en `notification_audit`).

---

## Decisión

### Cap duro de 500 items por click

```ruby
ids = DispatchQueue
  .where(status: "failed")
  .where("failed_reason LIKE ?", "#{reason}%")
  .order(:id)
  .limit(cap)   # default CAP = 500
  .pluck(:id)
```

Seguido de:

```ruby
DispatchQueue
  .where(id: ids, status: "failed")
  .update_all(status: "pending", attempts: 0, ...)
```

El doble filtro `WHERE id IN (...) AND status='failed'` dentro de la transacción garantiza que si el Worker ya procesó alguno de los ids entre el `pluck` y el `update_all`, esos jobs se saltan sin error.

### Una transacción + un audit consolidado

```ruby
ActiveRecord::Base.transaction do
  retried = DispatchQueue.where(id: ids, status: "failed").update_all(...)
  NotificationAudit.create!(
    notification_type: "_dlq_bulk_retried_",
    metadata: { count: retried, reason_filter: reason, retried_by: by }
  )
  { retried: retried, total: total }
end
```

Un solo audit con `count` y `reason_filter` en lugar de N audits individuales. Si el audit falla, toda la transacción revierte.

---

## Alternativas consideradas

| Opción | Pros | Contras | Descartada porque |
|--------|------|---------|-------------------|
| Sin cap | Operación única | DLQ con 10k items inundaría dispatch_queue; Worker degradado | Riesgo operacional inaceptable |
| Cap configurable por UI | Flexibilidad | Permite bypasear el límite de seguridad; UX más compleja | Cap duro es más simple y predecible |
| Background job (Sidekiq) para bulk | Sin cap necesario | Requiere Sidekiq; gema fuera de scope | Dependencia desproporcionada para operación admin ocasional |
| Cursor pagination del bulk | Sin límite de items por run | Complejidad mayor; UX "ejecutá de nuevo" es suficiente | Ideás sobre ingenierizar demás |

---

## Cap 500: justificación del número

- Worker `process_batch` procesa hasta 50 jobs por batch (default `batch_size=10`, ajustable).
- 500 jobs en `pending` = ~10 batches del Worker = evacuación en ~1 min con 1 worker a 10/batch.
- Máximo `dispatch_queue` capacity estimada: 10k jobs. 500 = 5% por operación. Safe.
- El usuario recibe feedback claro: "se reintentaron 500 de N" → puede hacer click de nuevo.

---

## Estado `failed` como DLQ

El Worker marca `status='failed'` cuando `attempts >= MAX_ATTEMPTS` (3). No se introdujo estado `dead` separado porque `failed` ya cumple el rol de DLQ terminal en la implementación existente. Se mantiene para no romper el modelo de estados. El nuevo estado `discarded` (Phase 9) diferencia jobs descartados manualmente de los que fallaron automáticamente.

---

## Consecuencias

**Positivas**:
- Operaciones evacúa DLQ de 200 jobs en ≤ 2 clicks (filtrar + reintentar todos), en < 30 s.
- Un audit consolidado por operación bulk mantiene el log de auditoría limpio.
- Transaccionalidad garantiza consistencia: o todos los jobs se reintentan o ninguno.

**Negativas / Trade-offs**:
- Si hay > 500 jobs del mismo motivo, requiere N clicks. Aceptable: operaciones controla el ritmo.
- El `total` se calcula antes de la transacción → puede diferir del `retried` real si hay concurrencia extrema. Impacto: el mensaje flash puede mostrar un total ligeramente desactualizado. Workaround: el usuario puede volver a filtrar y ver el estado real.

---

## Referencias

- [ADL-005](ADL-005-skip-locked-job-claiming.md) — `FOR UPDATE SKIP LOCKED` en el Worker (evita race con bulk retry).
- [specs/008-admin-templates-dlq/research.md](../specs/008-admin-templates-dlq/research.md) — R3 (cap y transaccionalidad), R4 (last_error_class).
