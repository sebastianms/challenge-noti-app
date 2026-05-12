# Data Model — 008-admin-templates-dlq

## Tabla nueva: `notification_templates`

| Columna | Tipo | Constraints | Descripción |
|---------|------|-------------|-------------|
| `id` | bigserial | PK | — |
| `notification_type` | text | NOT NULL | Discriminador (ej. `birthday`, `mfa`) |
| `locale` | text | NOT NULL DEFAULT `'es'` | Reservado para i18n futura |
| `title` | text | NOT NULL | Plantilla `{{var}}` para el título |
| `body` | text | NOT NULL | Plantilla `{{var}}` para el cuerpo |
| `digest_template` | text | NULL | Plantilla agregada (formato libre) |
| `created_at` | timestamptz | NOT NULL | — |
| `updated_at` | timestamptz | NOT NULL | — |

**Índices**:
- `UNIQUE (notification_type, locale)` — un solo override por par.

**Validaciones AR**:
- `notification_type`: presence, format `/\A[a-z_]+\z/`
- `title`, `body`: presence, max 2000 chars
- `digest_template`: optional, max 4000 chars

**Callbacks**:
- `after_save`: `TemplateCache.invalidate(notification_type, locale)`
- `after_destroy`: `TemplateCache.invalidate(notification_type, locale)`

---

## Cambio en `dispatch_queue` (existente)

**Migration**: extender CHECK constraint en `status`.

```sql
ALTER TABLE dispatch_queue DROP CONSTRAINT dispatch_queue_status_check;
ALTER TABLE dispatch_queue ADD CONSTRAINT dispatch_queue_status_check
  CHECK (status IN ('pending','in_flight','done','failed','dead','discarded'));
```

Estados resultantes:

| Status | Significado |
|--------|-------------|
| `pending` | listo para claim |
| `in_flight` | claim activo por worker |
| `done` | entregado |
| `failed` | error transitorio, espera backoff |
| `dead` | MAX_ATTEMPTS alcanzado, en DLQ |
| `discarded` (NEW) | operaciones descartó manualmente |

**Transiciones nuevas**:
- `dead → pending` (reintento, también resetea `attempts=0`, `available_at=NOW()`)
- `dead → discarded`

---

## Cambio en `notification_audit` (existente)

Sin schema change. Solo nuevos `notification_type` de audit:

| `notification_type` | Generado por | `metadata` keys |
|---------------------|--------------|-----------------|
| `_dlq_retried_` | `DlqRetrier.call` (individual) | `retried_by` (email), `job_id`, `original_attempts` |
| `_dlq_bulk_retried_` | `DlqRetrier.bulk_call` | `retried_by`, `count`, `reason_filter` |
| `_dlq_discarded_` | `DlqDiscarder.call` | `discarded_by`, `reason`, `job_id` |

Convención `_<accion>_` igual que `_blacklist_removed_` de Phase 6.

---

## Entidades relacionadas (sin cambios)

- `NotificationRule`, `PendingDigest`, `NotificationBlacklist`, `AdminUser` permanecen iguales.

---

## Diagrama lógico

```
┌──────────────────────────┐         ┌─────────────────────┐
│ notification_templates   │         │ AbstractNotification │
│  (notification_type+lo-  │◄────────│  consulta override   │
│   cale UNIQUE)           │  cache  │  via TemplateResolver│
└──────────────────────────┘         └─────────────────────┘

┌──────────────────────────┐         ┌─────────────────────┐
│ dispatch_queue (status:  │         │ notification_audit  │
│  + discarded)            │────────►│  (_dlq_retried_,    │
│                          │ retried │   _dlq_bulk_retried_│
│                          │ discard │   _dlq_discarded_)  │
└──────────────────────────┘         └─────────────────────┘
```
