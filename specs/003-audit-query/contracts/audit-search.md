# Contract: `GET /admin/audits`

## Request

**Method**: `GET`
**Path**: `/admin/audits`
**Auth**: HTTP Basic (`AUDIT_BASIC_AUTH_USER` / `AUDIT_BASIC_AUTH_PASSWORD`)

### Query params (todos opcionales)

| Param | Tipo | Ejemplo | Notas |
|---|---|---|---|
| `correlation_id` | UUID | `uuid-abc-123` | Si presente, ignora los otros filtros y retorna timeline ordenado |
| `recipient` | string | `juan@example.com` | Match exacto contra `recipient_canonical` |
| `status` | string | `failed` | Match exacto |
| `from` | ISO date | `2026-05-01` | Inclusive |
| `to` | ISO date | `2026-05-31` | Inclusive (interpretado como fin de día) |
| `source` | string | `sendgrid_webhook` | Opcional: `internal` o `sendgrid_webhook` |
| `page` | int | `1` | Default 1 |
| `per_page` | int | `50` | Default 50, max 50 |

## Response

### 200 OK — render HTML (Hotwire)

Template `app/views/admin/audits/index.html.erb`:

- Form de filtros (sticky en el top)
- Tabla con columnas: `created_at`, `correlation_id`, `recipient_canonical`, `status`, `source`, `channel`
- Paginación: `<< 1 2 [3] 4 5 >>` con links a la misma ruta con `page=N`
- Total de resultados visible

### 401 Unauthorized

- HTTP Basic challenge. Sin body.

## Invariantes

- Si `correlation_id` está presente, los demás filtros se ignoran y los resultados se ordenan por `created_at ASC` (timeline).
- Si `correlation_id` está ausente, los resultados se ordenan por `created_at DESC` (más recientes primero).
- `per_page` está capped en 50 server-side aunque el cliente envíe un valor mayor.
- Los filtros se aplican como `AND` lógico.
- Sin resultados → renderiza la tabla vacía con mensaje "Sin coincidencias", no un 404.
