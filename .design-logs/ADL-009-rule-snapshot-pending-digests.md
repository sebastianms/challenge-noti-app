# ADL-009: Snapshot de regla en pending_digests vs. foreign key

**Fecha**: 2026-05-12
**Estado**: Aceptado
**Feature**: 004-rules-engine (PendingDigest)

## Contexto

Cuando un evento queda en `pending_digests` esperando consolidación, puede pasar tiempo (minutos a horas según `digest_window_seconds`) antes de que `DigestScheduler` lo procese. Durante ese tiempo, la regla que originó la decisión puede ser editada o eliminada.

FR-010 del spec exige que los items pendientes NO se descarten si la regla se borra: se procesan con la configuración con la que entraron, garantizando determinismo del comportamiento que el usuario esperaba al disparar el envío.

## Decisión

Persistir un campo `rule_snapshot JSONB` en cada fila de `pending_digests` con la configuración relevante de la regla al momento del INSERT (`rule_id`, `digest_window_seconds`, `channels`, `priority`). El scheduler lee del snapshot — no consulta nuevamente `notification_rules`.

```ruby
PendingDigest.create!(
  ...
  rule_snapshot: {
    rule_id:                rule.id,
    digest_window_seconds:  rule.digest_window_seconds,
    channels:               rule.channels,
    priority:               rule.priority
  }
)
```

No hay FK desde `pending_digests.rule_id` hacia `notification_rules.id`. La relación es por valor en el JSONB.

## Alternativas consideradas

1. **FK con `ON DELETE SET NULL`**: descartada. Al borrarse la regla, el item queda huérfano (`rule_id = NULL`) sin contexto para procesarlo. El scheduler tendría que adivinar la ventana o aplicar un default arbitrario.
2. **FK con `ON DELETE RESTRICT`**: descartada. Bloquea la eliminación de una regla mientras haya items pendientes en cola. UX confuso para Producto, que esperaría poder "cancelar" una regla sin tener que vaciar primero la cola.
3. **FK con `ON DELETE CASCADE`**: descartada. Borra los items pendientes silenciosamente, violando FR-010.
4. **Replicar columnas (`digest_window_seconds`, `channels`, etc.) en `pending_digests`**: descartada. JSONB con snapshot es más flexible — agregar campos a la regla en el futuro no requiere ALTER TABLE.

## Consecuencias

**Positivas**:
- FR-010 cumplido: cambios o borrados de regla NO afectan items en cola.
- Comportamiento determinista: lo que el usuario disparó es lo que se ejecuta.
- Flexibilidad de esquema: nuevos campos de regla se suman al snapshot sin migración.

**Negativas / trade-offs**:
- No hay garantía de integridad referencial por DB. Si se debuggea un item con `rule_id=42`, hay que aceptar que la regla original puede ya no existir.
- Auditing post-hoc requiere parsear JSONB en lugar de joinar — mitigado por la naturaleza efímera de `pending_digests` (consolidados en minutos).
- Tamaño de fila ligeramente mayor por el JSONB. Inconsecuente — los items se consolidan rápidamente y se pueden purgar.

## Referencias

- Implementación: `app/central/ingestion/event_builder.rb` (método `enqueue_digest`)
- Migración: `db/migrate/20260512000002_create_pending_digests.rb`
- Tests: `spec/central/broker/digest_scheduler_spec.rb`
- FR relacionados: FR-005, FR-006, FR-010 del spec 004
