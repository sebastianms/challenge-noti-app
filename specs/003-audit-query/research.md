# Research — 003-audit-query

## R1 — Firma de webhooks de SendGrid Event Webhook

### Decisión

Validar la firma con **Ed25519** (no HMAC-SHA256) usando la public key de SendGrid.

### Detalle técnico

SendGrid Event Webhook v3 (Signed Webhooks) firma cada request con Ed25519. La verificación requiere:

- **Headers recibidos**:
  - `X-Twilio-Email-Event-Webhook-Signature` — firma Ed25519 en base64.
  - `X-Twilio-Email-Event-Webhook-Timestamp` — timestamp Unix del envío.
- **Mensaje a verificar**: `timestamp + raw_body` (string concatenación).
- **Clave pública**: provista por SendGrid en su portal al activar Signed Webhooks. Se carga vía env var `SENDGRID_WEBHOOK_PUBLIC_KEY`.
- **Librería Ruby**: `ed25519` gem (~1.x). Solo agrega ~30 KB y es pure-Ruby con bindings nativos opcionales.

### Rationale

Mantener compatibilidad con SendGrid sin alternativas. Ed25519 ofrece firmas más cortas y rápidas que RSA y la API de SendGrid es la única expuesta como contrato externo.

### Alternativas rechazadas

| Alternativa | Razón de rechazo |
|---|---|
| HMAC-SHA256 con shared secret | SendGrid no lo ofrece para Event Webhooks |
| Sin verificación | Violación de seguridad: cualquiera puede inyectar entradas a `notification_audit` |
| OAuth2 entre SendGrid y nuestra app | No soportado para webhook delivery |

### ADL

Se documenta como **ADL-007** durante implementación.

---

## R2 — Backfill de `recipient_canonical` en filas existentes de `notification_audit`

### Decisión

**No backfill.** La columna se agrega como `NULLable`. Los datos en disco son de desarrollo y tests; no hay producción que migrar.

### Rationale

- Costo de backfill (JOIN con `notification_events`) es mayor al valor en este entorno.
- US2 (búsqueda por destinatario) opera sobre datos nuevos creados a partir de la migración.
- Si futuro requiere backfill, es una migración aislada de un solo SQL.

---

## R3 — Pagination en Hotwire sin librerías externas

### Decisión

Paginación manual con parámetros `page` y `per_page` (cap 50). Cada navegación renderiza la página completa (no Turbo Frame incremental — sobre-ingenería para esta fase).

### Detalle

- Default `per_page = 50`.
- Query: `LIMIT 50 OFFSET (page-1)*50`.
- Conteo total con `COUNT(*)` separado (aceptable para volúmenes ≤ 1M filas; las particiones aceleran el escaneo por rango de fechas).

### Alternativas rechazadas

| Alternativa | Razón de rechazo |
|---|---|
| Gema Kaminari/Pagy | Una dependencia para algo trivial; OFFSET nativo basta |
| Keyset pagination | Más eficiente con datasets grandes, pero rompe la UX simple "página N de M"; lo dejamos para Phase 7 si la latencia lo justifica |
| Turbo Frame incremental con infinite scroll | Más complejo en UI; soporte usa filtros para descartar, no scrollea |

---

## R4 — Estrategia del PartitionManager

### Decisión

- `create_next_month_partition`: idempotente (`CREATE TABLE IF NOT EXISTS`). Calcula el rango `[next_month_start, next_month_start + 1.month)`.
- `drop_old_partitions(retention_months:)`: itera particiones existentes con `pg_partitions` (o `pg_inherits`), identifica las que cierran antes de `Time.now - retention_months.months`, y las dropea con `DROP TABLE IF EXISTS`.
- **Safety guardrail**: nunca dropea una partición cuyo rango incluya datos de menos de 3 meses, independientemente de la retención configurada. Si la retención configurada es `< 3` meses, log de warning y se respeta el mínimo de 3.

### Rationale

PostgreSQL 17 soporta particionamiento declarativo (ya usado en `notification_events` y `notification_audit`). El manejo manual via SQL evita dependencias como `pg_partman`.

### Alternativas rechazadas

| Alternativa | Razón de rechazo |
|---|---|
| `pg_partman` extension | Requiere instalación de extensión en RDS, sobre-ingeniería para 1 tabla |
| `pg_cron` extension | Extensión adicional; mejor invocar desde rake task externo |
| Solid Cron / cron del SO | Phase 10 lo integra; en esta fase basta con rake invocable manualmente |

---

## R5 — HTTP Basic auth en Rails 8

### Decisión

`http_basic_authenticate_with` nativo de `ActionController::HttpAuthentication::Basic`, con credenciales desde `Rails.application.credentials` o env vars.

```ruby
class Admin::AuditsController < ApplicationController
  http_basic_authenticate_with(
    name:     ENV.fetch("AUDIT_BASIC_AUTH_USER"),
    password: ENV.fetch("AUDIT_BASIC_AUTH_PASSWORD")
  )
end
```

### Rationale

Cero dependencias, integrado en Rails. Suficiente como placeholder hasta Phase 7. En tests, se envía el header `Authorization: Basic <base64>` con las credenciales esperadas.

---

## R6 — Procesamiento async vs. inline del webhook

### Decisión

**Async via tabla intermedia** `webhook_events`:

1. Controller valida firma → persiste raw payload con `status = pending` → 200 OK.
2. `WebhookEventWorker.process_batch` reclama filas con `FOR UPDATE SKIP LOCKED LIMIT N`, las marca `processing`.
3. Por cada fila: itera el array de eventos del payload, crea entradas en `notification_audit` (`source = sendgrid_webhook`), commit, marca `processed`.
4. Si falla (excepción del proceso), `status = failed` con `failed_reason`.

### Rationale

- El SLA del webhook con SendGrid es responder < 5 s; persistir + responder rápido < 100 ms es trivial.
- Aísla el procesamiento del request; un bug en el processor no bloquea la respuesta y SendGrid no reintenta.
- Reusa el patrón SKIP LOCKED ya validado en `dispatch_queue` (ADL-005).

### Reintentos

- En esta fase, **no hay backoff** para `webhook_events` fallidos: status `failed` queda en disco para inspección manual.
- En Phase 10 se evalúa si conviene reintento automático.

---

## Resumen de dependencias nuevas

| Gema | Versión | Razón |
|---|---|---|
| `ed25519` | `~> 1.3` | Verificación de firma Ed25519 de SendGrid Event Webhook |

Sin más dependencias. No agregamos paginación, autenticación ni cron externos.
