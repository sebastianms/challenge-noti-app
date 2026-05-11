# ADL-010: Evaluación de blacklist antes del RulesEngine + transaccionalidad del webhook

**Fecha**: 2026-05-12
**Estado**: Aceptado
**Feature**: 005-blacklist-bounces

## Contexto

`notification_blacklist` materializa el opt-out duro de compliance: una vez que un destinatario está bloqueado (manualmente o por hard bounce/dropped/spamreport de SendGrid), ningún envío del scope bloqueado puede salir. Hay tres dimensiones independientes (`global`, `type`, `channel`) que se evalúan por destinatario canonical.

Dos decisiones se tomaron en conjunto y conviene documentarlas juntas:

1. **Dónde** colocar la evaluación de blacklist dentro del pipeline de ingestion.
2. **Cómo** garantizar que un evento webhook que reporta hard bounce nunca deje el sistema en estado intermedio (audit sin blacklist o blacklist sin audit).

## Decisión

### 1. Evaluación pre-reglas

`BlacklistEvaluator.match` se invoca **dentro de la transacción de persistencia** en `EventBuilder`, después del check de idempotencia (UNIQUE en `notification_events`) y **antes** de `RulesEngine.decide`. Si encuentra fila → audit `filtered` con `metadata = { reason: "blacklisted", blacklist_id, scope, target }` + retorno `SendResult.filtered`. Sin match → flujo normal hacia `RulesEngine.decide` → dispatch/digest/filter.

```ruby
if (entry = BlacklistEvaluator.match(event: ..., channel: "email"))
  audit_blacklisted(correlation_id:, event_id:, ..., entry:)
  SendResult.filtered(correlation_id:)
else
  apply_decision(...)  # RulesEngine + Enqueuer/PendingDigest
end
```

La query es única con OR y `LIMIT 1`, soportada por `idx_blacklist_lookup (recipient_canonical, scope)`:

```sql
SELECT id, scope, target, source FROM notification_blacklist
WHERE recipient_canonical = $1
  AND (scope = 'global'
       OR (scope = 'type'    AND target = $2)
       OR (scope = 'channel' AND target = $3))
LIMIT 1
```

### 2. Transaccionalidad del webhook

`SendgridEventProcessor.process_one` envuelve `create_audit` + `blacklist_if_hard_failure` en una sola transacción de AR. El insert de blacklist usa `insert_all(..., unique_by: :idx_blacklist_unique)` para hacer `ON CONFLICT DO NOTHING` (idempotente frente a webhooks repetidos).

```ruby
ActiveRecord::Base.transaction do
  create_audit(evt)
  blacklist_if_hard_failure(evt)
end
```

Si el insert de blacklist falla, el audit rollbackea (verificado en spec).

## Alternativas consideradas

1. **Rama dentro de `RulesEngine`** (early-return en `decide`): descartada. Mezcla compliance con configuración editable; aumenta la superficie del módulo de reglas y obliga a cargar `RuleCache` aunque ya sepamos que vamos a filtrar.
2. **Hook post-encolado** (filtrar en `Worker#dispatch`): descartada. Rompe SC-005 (queda fila huérfana en `dispatch_queue`) y agrega trabajo innecesario al broker para algo que ya sabemos a la entrada.
3. **`after_create` callback en `NotificationAudit`** (auto-blacklist desde el audit de bounced): descartada. Acoplamiento sutil entre módulos + race entre worker que escribe audit y callback que lee.
4. **Endpoint separado para bounces** (`Webhooks::SendgridBouncesController`): descartada. Contradice ADL-007 ("un solo webhook firmado"). El controller actual ya recibe TODOS los eventos de SendGrid.
5. **Audit + blacklist en transacciones separadas**: descartada. Una falla intermedia dejaría inconsistencia visible (destinatario auditado como bounced pero sin bloqueo, o bloqueado pero sin trazabilidad del evento original).

## Consecuencias

### Positivas

- Compliance no negociable: nadie puede levantar el veto por configuración de reglas.
- Latencia mínima añadida: 1 query con LIMIT 1 antes de `RulesEngine` (5 ms p95 a 100k filas, ver quickstart benchmark SC-005).
- Idempotencia y consistencia garantizadas por el par UNIQUE NULLS NOT DISTINCT + transacción.
- Reutilización completa del webhook existente (ADL-007) y de `NotificationAudit` particionado (ADL-001).

### Negativas

- El evento queda persistido en `notification_events` aunque sea filtrado por blacklist. Es deliberado: queremos correlation_id y trazabilidad del intento, pero implica que el throughput de inserts a `notification_events` incluye eventos que nunca verán dispatch. Mitigación: el costo es bajo y el insight de "intentos bloqueados por compliance" es valioso para Producto.
- La transacción del webhook abarca dos tablas: si `notification_blacklist` crece mucho o cambia su esquema, el lock period sube. Mitigación: índices `(recipient_canonical, scope, target)` + `insert_all` (no AR object instanciado).

## Referencias

- `specs/005-blacklist-bounces/research.md` — R1 (posición pre-reglas), R2 (query única), R3 (reuso del webhook unificado), R5 (audit trail de remoción), R7 (canonicalización en ambos lados).
- `specs/005-blacklist-bounces/spec.md` — SC-005 (p95 ≤ 5 ms).
- ADL-007 — un solo webhook firmado con Ed25519.
- ADL-001 — `notification_audit` particionado por idempotency_window_ts.
