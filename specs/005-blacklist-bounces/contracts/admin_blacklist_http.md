# Contract — HTTP `/admin/blacklist`

Reutiliza autenticación HTTP Basic de `/admin/audits` (`AUDIT_BASIC_AUTH_USER` / `AUDIT_BASIC_AUTH_PASSWORD`).

## `GET /admin/blacklist`

**Query params** (todos opcionales):
- `recipient` — string, match por canónico (lowercase + trim antes de consultar).
- `scope` — uno de `global | type | channel`.
- `target` — string, exacto.
- `source` — uno de `manual | admin_ui | hard_bounce | dropped | spamreport`.
- `page` — entero ≥ 1, default 1.
- `per_page` — entero ≤ 50, default 25.

**Response 200**: HTML Hotwire con tabla:

| recipient_canonical | scope | target | source | reason | created_at | acciones |
|---------------------|-------|--------|--------|--------|------------|----------|

Paginación inferior (anterior/siguiente). Form de filtros arriba.

**Response 401**: si HTTP Basic falla.

## `POST /admin/blacklist`

**Body (form-urlencoded)**:
- `recipient_canonical` (required)
- `scope` (required) — `global | type | channel`
- `target` (required si scope ≠ global)
- `reason` (required)

**Response 302 → /admin/blacklist** con flash de éxito. Crea fila con `source=admin_ui`. Pasa `recipient_canonical` por `RecipientNormalizer.canonicalize` antes de insertar.

**Response 422**: si validaciones fallan (CHECK constraint o normalizer retorna nil).

## `DELETE /admin/blacklist/:id`

Implementado como `POST /admin/blacklist/:id?_method=delete` (Rails convention).

**Body**:
- `reason` (required) — justificación del removal.

**Comportamiento**:
1. Crea audit `blacklist_removed` con metadata `{blacklist_id, scope, target, removed_by: request.env["HTTP_AUTHORIZATION"]→user, reason}`.
2. DELETE de la fila.

Ambos pasos en una transacción.

**Response 302 → /admin/blacklist** con flash de éxito.

**Response 404**: si `id` no existe.

## Sin endpoints JSON

UI Hotwire renderiza HTML server-side. No hay API JSON pública. Para automatización, usar consola Rails.
