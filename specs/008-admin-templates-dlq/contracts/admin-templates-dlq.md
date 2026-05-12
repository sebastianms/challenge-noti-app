# HTTP Contracts — admin/templates & admin/dlq

Todas las rutas requieren sesión Devise (`authenticate_admin_user!`) y autorización por sección (`RoleAuthorizer`). Cualquier acceso sin sesión → `302` a `/admin/login`. Acceso sin permiso → `403`.

## Templates (sección `:templates`, roles `admin`, `product`)

| Verb | Path | Body / Params | Response | Notas |
|------|------|---------------|----------|-------|
| GET | `/admin/templates` | — | `200` HTML lista | Paginación cap 50 |
| GET | `/admin/templates/new` | — | `200` HTML form | — |
| POST | `/admin/templates` | `notification_type`, `locale?`, `title`, `body`, `digest_template?` | `302 → /admin/templates` o `422` HTML form con errors | Crea override |
| GET | `/admin/templates/:id/edit` | — | `200` HTML form + preview vacío | — |
| PATCH | `/admin/templates/:id` | mismo set | `302` o `422` | Actualiza override; invalida cache |
| DELETE | `/admin/templates/:id` | — | `302 → /admin/templates` | Borra override; vuelve al fallback Ruby |
| POST | `/admin/templates/:id/preview` | `title`, `body`, `digest_template?`, `context_json` | `200` HTML parcial (turbo-frame `preview`) con `{rendered, missing_keys}` | No persiste; solo renderiza |

## DLQ (sección `:dlq`, roles `admin`, `engineering`)

| Verb | Path | Body / Params | Response | Notas |
|------|------|---------------|----------|-------|
| GET | `/admin/dlq` | `reason?` (filtra por `last_error_class`) | `200` HTML agrupado | Sin filtro: lista grupos con counts |
| POST | `/admin/dlq/:id/retry` | — | `302 → /admin/dlq` | Individual; audit `_dlq_retried_` |
| POST | `/admin/dlq/bulk_retry` | `reason` (string) | `302 → /admin/dlq` con flash `count_retried/count_total` | Cap 500; audit `_dlq_bulk_retried_` |
| POST | `/admin/dlq/:id/discard` | `reason` (presence) | `302 → /admin/dlq` o `422` si falta motivo | audit `_dlq_discarded_` |

## Códigos de error compartidos

- `401` no se usa — Devise redirige.
- `403` siempre como render directo desde `Admin::BaseController#authorize_section!`.
- `404` cuando `:id` no existe (Rails default).
- `422` validación AR fallida — re-render form.

## Audit payloads (insertados en `notification_audit`)

```jsonb
// _dlq_retried_
{ "retried_by": "ops@example.com", "job_id": 123, "original_attempts": 3 }

// _dlq_bulk_retried_
{ "retried_by": "ops@example.com", "count": 500, "reason_filter": "Net::OpenTimeout" }

// _dlq_discarded_
{ "discarded_by": "ops@example.com", "reason": "recipient inválido", "job_id": 123 }
```

`correlation_id` de cada audit: `SecureRandom.uuid` (operación admin, sin envío real asociado).
