# Research — 005-blacklist-bounces

## R1 — Posición de `BlacklistEvaluator` en el pipeline

**Decisión**: invocar `BlacklistEvaluator` **antes** de `RulesEngine.decide` en `EventBuilder#perform`. Si matchea → corto-circuito: audit `filtered` con `reason=blacklisted`, no se inserta en `dispatch_queue` ni en `pending_digests`.

**Razón**: la blacklist es veto absoluto de compliance — ninguna regla puede levantarla. Posicionarla pre-reglas evita gastar el lookup de `RuleCache` cuando ya sabemos que el evento se filtra.

**Alternativas**:
- Evaluación dentro del `RulesEngine` como rama temprana → mezcla compliance con configuración editable; aumenta superficie del módulo de reglas.
- Evaluación en el `Worker` (después de encolar) → rompe SC-005 (queda fila huérfana en `dispatch_queue`) y agrega trabajo innecesario al broker.

## R2 — Query única vs. tres queries

**Decisión**: query única con OR sobre las tres dimensiones.

```sql
SELECT id, scope, target, source FROM notification_blacklist
WHERE recipient_canonical = $1
  AND (scope = 'global'
       OR (scope = 'type'    AND target = $2)
       OR (scope = 'channel' AND target = $3))
LIMIT 1;
```

Índice de soporte: `(recipient_canonical, scope, target)` — cubre el filtro completo. Postgres puede usarlo con la condición OR si el plan es bitmap-OR; con pocas filas por destinatario (raro tener > 5), el scan es O(filas-del-recipient).

**Razón**: 1 round-trip vs. 3. La blacklist por destinatario tiene cardinalidad baja (1-3 filas típicamente). LIMIT 1 corta apenas hay match.

**Alternativas**:
- 3 queries secuenciales → 3× round-trips, peor SC-005.
- Cache en `Rails.cache` por destinatario → invalidación frágil (mil destinatarios distintos), TTL no ayuda porque cada destinatario único se consulta una vez. Descartado.

## R3 — Integración con webhook existente vs. controller nuevo

**Decisión**: extender `WebhookEventWorker#process_event` (feature 003). NO crear `Webhooks::SendgridBouncesController` (mencionado en roadmap original, ahora obsoleto porque el webhook unificado de 003 ya recibe TODOS los tipos de eventos, incluyendo bounces).

```ruby
case event["event"]
when "bounce"
  audit_bounce(event)
  blacklist_if_hard(event)  # ← nuevo
when "dropped", "spamreport"
  audit_event(event)
  blacklist_recipient(event, source: event["event"])  # ← nuevo
when "deferred"
  audit_event(event)  # solo audit, no blacklist
end
```

**Razón**: DRY — el endpoint `POST /webhooks/sendgrid`, la verificación Ed25519, la persistencia en `webhook_events` y el SKIP LOCKED ya existen. Crear un controller paralelo sería duplicación injustificada.

**Alternativas**:
- Endpoint separado con su propia firma/persistencia → contradice ADL-007 (1 webhook, 1 firma).
- Hook callback `after_create` en `NotificationAudit` cuando status=bounced → sutil acoplamiento + race entre worker que escribe audit y callback que lee.

## R4 — `source` enum: granularidad

**Decisión**: 5 valores: `manual`, `admin_ui`, `hard_bounce`, `dropped`, `spamreport`.

**Razón**: trazabilidad fina para compliance. Soporte necesita responder "¿por qué este usuario está bloqueado?" — `hard_bounce` vs. `spamreport` vs. `manual` tienen tratamientos legales distintos. La diferencia `manual` (consola) vs. `admin_ui` (form web) ayuda a auditar quién/cómo.

**Alternativas**:
- Solo `automatic` vs. `manual` → pierde detalle de tipo de evento de SendGrid. Descartado.

## R5 — Modelo de remoción con audit trail

**Decisión**: `DELETE FROM notification_blacklist WHERE id = $1` físico. Antes del DELETE, crear fila en `notification_audit` con:
- `notification_type` = `_blacklist_removed_` (sintético, prefijo `_` para indicar evento administrativo)
- `correlation_id` = `gen_random_uuid()` (nuevo)
- `status` = `blacklist_removed`
- `source` = `internal`
- `recipient_canonical` = el destinatario removido
- `metadata` = `{blacklist_id, scope, target, removed_by, reason}`

`removed_by` viene del HTTP Basic user (`AUDIT_BASIC_AUTH_USER`) o `"console"` si es desde Rails console.

**Razón**: reutiliza la tabla particionada existente, evita schema nuevo. El prefijo `_` en `notification_type` lo distingue de tipos reales en queries.

**Alternativas**:
- Tabla `blacklist_audit` dedicada → schema nuevo, particionamiento aparte. Sobre-ingeniería para volumen bajo (remociones son raras).
- Soft delete (`deleted_at`) → complica UNIQUE: tras restore, hay que rehidratar. Descartado.

## R6 — Validación del CHECK de scope/target

**Decisión**: constraint a nivel DB + validación AR redundante.

```sql
CHECK (
  (scope = 'global'  AND target IS NULL) OR
  (scope IN ('type', 'channel') AND target IS NOT NULL)
)
```

**Razón**: defense in depth — la DB es la última línea contra bugs. Validación AR permite mensajes de error legibles en la UI.

## R7 — `recipient_canonical` source-of-truth

**Decisión**: TODOS los INSERTs (manual, webhook, UI) pasan por `Central::Ingestion::RecipientNormalizer.canonicalize(raw)`. Si retorna `nil` → log warning y skip (no se inserta basura).

**Razón**: garantiza que el lookup de `BlacklistEvaluator` (que también usa `recipient_canonical` del evento) matchee siempre, sin importar la casing/whitespace del input original.
