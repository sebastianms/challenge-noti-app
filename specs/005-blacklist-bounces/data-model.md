# Data Model — 005-blacklist-bounces

## Tabla `notification_blacklist`

```sql
CREATE TABLE notification_blacklist (
  id                  BIGSERIAL PRIMARY KEY,
  recipient_canonical VARCHAR(320) NOT NULL,
  scope               VARCHAR(16)  NOT NULL,
  target              VARCHAR(64),
  source              VARCHAR(32)  NOT NULL,
  reason              TEXT,
  created_at          TIMESTAMPTZ  NOT NULL DEFAULT CLOCK_TIMESTAMP(),

  CONSTRAINT blacklist_scope_target_chk CHECK (
    (scope = 'global' AND target IS NULL)
    OR (scope IN ('type', 'channel') AND target IS NOT NULL)
  ),
  CONSTRAINT blacklist_scope_values_chk CHECK (
    scope IN ('global', 'type', 'channel')
  ),
  CONSTRAINT blacklist_source_values_chk CHECK (
    source IN ('manual', 'admin_ui', 'hard_bounce', 'dropped', 'spamreport')
  )
);

-- Idempotencia: una sola entrada por (recipient, scope, target).
-- NULLS NOT DISTINCT (Postgres 15+) trata global+NULL como único.
CREATE UNIQUE INDEX idx_blacklist_unique
  ON notification_blacklist (recipient_canonical, scope, target)
  NULLS NOT DISTINCT;

-- Cubre el lookup principal del BlacklistEvaluator
CREATE INDEX idx_blacklist_lookup
  ON notification_blacklist (recipient_canonical, scope);

-- Soporta filtros de la UI admin (browse por source/scope)
CREATE INDEX idx_blacklist_source_created
  ON notification_blacklist (source, created_at DESC);
```

### Campos

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | BIGSERIAL | PK. |
| `recipient_canonical` | VARCHAR(320) | Email canonicalizado (lowercase + trim). 320 = límite RFC 5321. |
| `scope` | VARCHAR(16) | `global` / `type` / `channel`. |
| `target` | VARCHAR(64) | Nullable. Si `scope=type` → notification_type (ej. `birthday`). Si `scope=channel` → nombre de canal (ej. `email`). NULL si `scope=global`. |
| `source` | VARCHAR(32) | Origen: `manual` (consola), `admin_ui` (UI web), `hard_bounce` / `dropped` / `spamreport` (webhook SendGrid). |
| `reason` | TEXT | Justificación libre. Para auto-blacklist desde webhook se persiste el mensaje de SendGrid (ej. `reason: "550 5.1.1 mailbox does not exist"`). |
| `created_at` | TIMESTAMPTZ | CLOCK_TIMESTAMP (consistente con ADL-004). |

### Reglas de integridad

- **UNIQUE `(recipient_canonical, scope, target)` con NULLS NOT DISTINCT**: permite `ON CONFLICT DO NOTHING` idempotente para auto-blacklist desde webhook. Sin `NULLS NOT DISTINCT`, dos filas `scope=global, target=NULL` para el mismo recipient se aceptarían (Postgres trata NULL ≠ NULL por default).
- **CHECK scope/target**: garantiza coherencia semántica. Sin esto, un INSERT con `scope=global, target='email'` pasaría silenciosamente y rompería la lógica del evaluator.
- **Sin FK a `recipient_id`**: la blacklist es por canónico, no por user-id del monolito. Independiza el módulo.

## Cambios en `notification_audit`

Sin cambios de schema. Se reutilizan columnas existentes:

- Nuevo valor de `status` en filas de filtrado: `filtered` (ya existe) con `metadata.reason = "blacklisted"` y `metadata.blacklist_id`.
- Nuevo valor de `status` para remoción: `blacklist_removed`. `notification_type = "_blacklist_removed_"`.

```sql
-- Ningún ALTER. Solo nuevos valores de string en columnas existentes.
```

## Relación de entidades

```
NotificationBlacklist  (1) ──[trazabilidad por metadata.blacklist_id]──> (N) NotificationAudit
                                                                              (status=filtered, reason=blacklisted)

WebhookEvent  (1) ──[process_event]──> (0..1) NotificationBlacklist  (source ∈ {hard_bounce, dropped, spamreport})
                                       (0..1) NotificationAudit       (status=bounced|dropped|spamreport, source=sendgrid_webhook)
```

## Volúmenes esperados

- **Filas**: 10k-100k para una operación normal (asume ~0.1% de hard bounces sobre ~10M envíos/mes).
- **Lookups**: 1 por evento ingresado → 140 rps en pico. Cubierto por `idx_blacklist_lookup`.
- **Inserts**: ~10/hora desde webhook, ~1/día desde manual/admin. Bajo.
- **Deletes**: ~1/semana desde admin. Inconsecuente.
