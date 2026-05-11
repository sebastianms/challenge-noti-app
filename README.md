# Central de Notificaciones

[![Tests](https://github.com/sebastianms/challenge-noti-app/actions/workflows/test.yml/badge.svg)](https://github.com/sebastianms/challenge-noti-app/actions/workflows/test.yml)
[![RuboCop](https://github.com/sebastianms/challenge-noti-app/actions/workflows/lint.yml/badge.svg)](https://github.com/sebastianms/challenge-noti-app/actions/workflows/lint.yml)
[![Security](https://github.com/sebastianms/challenge-noti-app/actions/workflows/security.yml/badge.svg)](https://github.com/sebastianms/challenge-noti-app/actions/workflows/security.yml)
[![Coverage](badges/coverage.svg)](https://github.com/sebastianms/challenge-noti-app/actions/workflows/test.yml)

Plataforma de notificaciones centralizada para equipos internos. Un solo archivo por tipo de notificación, idempotencia garantizada por SHA256 + `UNIQUE` constraint en Postgres.

## Requisitos

- Ruby 3.3
- PostgreSQL 17
- Docker (para desarrollo local)

## Inicio rápido

### Con Docker (recomendado)

```bash
# Levantar base de datos y servidor de desarrollo
docker compose up -d postgres app

# Crear y migrar la base de datos (primera vez)
docker compose exec app bin/rails db:create db:migrate

# Correr los specs dentro del contenedor
docker compose run --rm test
```

### Sin Docker (Rails nativo)

```bash
docker compose up -d postgres       # solo la base de datos
bin/rails db:create db:migrate
bundle exec rspec
```

## Agregar una notificación nueva

Crea un archivo en `app/notifications/`:

```ruby
# app/notifications/birthday_notification.rb
class BirthdayNotification < AbstractNotification
  notification_type :birthday

  def self.title(context = {})
    "¡Feliz cumpleaños, #{context[:name]}!"
  end

  def self.body(_context = {})
    "Hoy te deseamos un excelente día."
  end
end
```

Invócala desde cualquier parte del monolito:

```ruby
result = BirthdayNotification.send("juan@example.com", context: { name: "Juan" })
result.created?        # => true
result.correlation_id  # => "uuid-..."
```

El segundo envío idéntico dentro de la ventana retorna `:duplicate` sin crear una fila nueva.

## Benchmark de carga

```bash
bundle exec rake bench:ingestion[140,60]   # 140 rps × 60 segundos
```

Reporta throughput real, p50/p95/p99 y cantidad de errores. Falla con código de salida 1 si p95 > 50 ms o hay errores.

## Desarrollo

### Con Docker

```bash
docker compose run --rm test                        # suite completa
docker compose run --rm test bundle exec rubocop    # lint
docker compose run --rm test bundle exec brakeman --no-pager
docker compose run --rm test bundle exec bundler-audit
```

### Sin Docker

```bash
bundle exec rspec                        # suite completa
bundle exec rubocop                      # lint
bundle exec brakeman --no-pager          # análisis de seguridad
bundle exec bundler-audit                # auditoría de dependencias
```

### Servicios Docker disponibles

| Servicio | Comando | Descripción |
|----------|---------|-------------|
| `postgres` | `docker compose up -d postgres` | Base de datos PostgreSQL 17 |
| `app` | `docker compose up app` | Rails dev server en `localhost:3000` |
| `test` | `docker compose run --rm test` | Corre `bundle exec rspec` y termina |

## Canales de entrega

El sistema usa un registro de canales (`ChannelRegistry`) que permite agregar nuevos proveedores sin modificar el core de ingesta.

### Email (SendGrid)

El canal de email está activo por defecto. Requiere dos variables de entorno:

| Variable | Descripción |
|----------|-------------|
| `SENDGRID_API_KEY` | API key de SendGrid |
| `SENDGRID_FROM_EMAIL` | Dirección remitente (ej. `noreply@example.com`) |

### Worker de despacho

El Worker procesa jobs de `dispatch_queue` en lotes. Puede ejecutarse en foreground con:

```bash
bin/rails worker:run                        # batch_size=10, sleep_interval=5s
bin/rails "worker:run[20,10]"               # batch_size=20, sleep_interval=10s
```

También puede ejecutarse dentro del contenedor:

```bash
docker compose exec app bin/rails worker:run
```

El Worker usa `FOR UPDATE SKIP LOCKED` para soportar múltiples instancias simultáneas sin duplicados. Implementa backoff exponencial (1m → 5m → 25m) y DLQ automático tras 3 intentos fallidos.

### Trazabilidad con SendGrid

Cada request a SendGrid incluye el `correlation_id` del evento en dos lugares:

- **Header HTTP `X-Correlation-ID`**: correlaciona logs de requests salientes.
- **`custom_args.correlation_id`** en el payload JSON: SendGrid lo persiste y lo incluye en webhooks de eventos (bounce, delivered, open), permitiendo cruzar eventos de entrega con registros de `notification_audit`:

```ruby
# En el handler de webhooks de SendGrid:
NotificationAudit.find_by(correlation_id: params[:correlation_id])
```

### Agregar un canal nuevo

```ruby
# app/central/channels/sms_channel.rb
class SmsChannel < ChannelStrategy
  def deliver(event, recipient_id, correlation_id:)
    # implementación...
    :delivered
  end

  def channel_name = "sms"
end
ChannelRegistry.register(:sms, SmsChannel.new)
```

## Motor de reglas

Cada notificación puede tener una regla en `notification_rules` que controla rate limit, cooldown, agrupación (digest) y canales habilitados. Sin regla, el comportamiento es el de Phase 3 (despacho sin restricciones).

Desde la consola Rails:

```ruby
NotificationRule.create!(
  notification_type:     "birthday",
  channels:              [ "email" ],
  max_per_day:           1,          # máximo 1 envío por destinatario en 24h
  cooldown_seconds:      60,         # 1 min entre envíos al mismo destinatario
  digest_window_seconds: 300,        # agrupa 5 min antes de despachar
  priority:              "standard", # o "critical" | "bulk"
  enabled:               true
)
```

Campos clave:

| Campo | Comportamiento |
|-------|----------------|
| `channels = NULL` | sin restricción |
| `channels = []`   | bloqueado (audit `filtered`, reason `disabled`) |
| `max_per_day`     | rate limit por `recipient_canonical` en ventana 24h |
| `cooldown_seconds`| tiempo mínimo entre envíos al mismo destinatario |
| `digest_window_seconds` | si presente, agrupa envíos en `pending_digests` |
| `priority`        | override del priority del llamante |
| `enabled = false` | regla pausada (tratada como inexistente) |

El cache de reglas (`Rails.cache`, TTL 5 min) garantiza que cambios se reflejen en ≤ 5 minutos sin reiniciar workers. La invalidación es sincrónica vía callbacks `after_save`/`after_destroy` (ver [ADL-008](.design-logs/ADL-008-rails-cache-rule-strategy.md)).

Items agrupables se persisten en `pending_digests` con un snapshot de la regla; sobreviven al borrado de la regla original (ver [ADL-009](.design-logs/ADL-009-rule-snapshot-pending-digests.md)). El worker `DigestScheduler` los consolida en 1 envío por grupo `(notification_type, recipient_canonical)`.

## Auditoría consultable

Cada envío deja un timeline de filas en `notification_audit` (`enqueued → dispatched → delivered | failed`). El endpoint `/admin/audits` permite consultarlo desde el navegador.

```
GET /admin/audits?correlation_id=<uuid>
GET /admin/audits?recipient=user@example.com&status=failed&from=2026-05-01
GET /admin/audits?source=sendgrid_webhook&page=2&per_page=50
```

Filtros combinables: `correlation_id`, `recipient`, `status`, `source`, `from`, `to`, `page`, `per_page` (cap 50). Si se pasa `correlation_id` retorna el timeline completo ASC; sin él, paginación DESC por `created_at`.

Variables de entorno:

| Variable | Descripción |
|----------|-------------|
| `AUDIT_BASIC_AUTH_USER` | Usuario HTTP Basic para `/admin/audits` |
| `AUDIT_BASIC_AUTH_PASSWORD` | Password HTTP Basic |
| `AUDIT_RETENTION_MONTHS` | Meses de retención para `partitions:rotate` (default 6, mínimo seguro 3) |

## Webhook de SendGrid

Endpoint async para recibir eventos de entrega de SendGrid (delivered, bounce, dropped, deferred, spamreport):

```
POST /webhooks/sendgrid
Headers:
  X-Twilio-Email-Event-Webhook-Signature: <base64 Ed25519>
  X-Twilio-Email-Event-Webhook-Timestamp: <unix ts>
Body: array JSON de eventos
```

El controller verifica la firma Ed25519, persiste el batch en `webhook_events` con status `pending` y responde 200 inmediatamente. `WebhookEventWorker` consume los pending vía `FOR UPDATE SKIP LOCKED` y traduce cada evento a una fila en `notification_audit` con `source = sendgrid_webhook`. Ver [ADL-007](.design-logs/ADL-007-ed25519-sendgrid-webhook-signature.md).

Variable requerida:

| Variable | Descripción |
|----------|-------------|
| `SENDGRID_WEBHOOK_PUBLIC_KEY` | Llave pública Ed25519 en Base64 (panel SendGrid → Mail Settings → Event Webhook) |

## Blacklist y opt-outs

Tabla `notification_blacklist` con tres dimensiones (`scope`): `global`, `type` o `channel`. El `BlacklistEvaluator` se ejecuta antes del motor de reglas; si matchea, el evento queda auditado como `filtered` con `reason=blacklisted` y nunca llega a `dispatch_queue`.

### Alta manual desde consola

```ruby
NotificationBlacklist.create!(
  recipient_canonical: "user@example.com",
  scope:               "global",   # o "type" / "channel"
  target:              nil,        # "birthday" para scope=type; "email" para scope=channel
  source:              "manual",
  reason:              "ticket #42"
)
```

| Campo | Valores | Descripción |
|-------|---------|-------------|
| `scope` | `global` / `type` / `channel` | Dimensión del bloqueo |
| `target` | `NULL` (si global), notification_type, o nombre de canal | Concreta el scope |
| `source` | `manual` / `admin_ui` / `hard_bounce` / `dropped` / `spamreport` | Trazabilidad de origen |
| `reason` | texto libre | Justificación; los webhooks embeben `sg_event_id` |

UNIQUE `(recipient_canonical, scope, target) NULLS NOT DISTINCT` garantiza idempotencia.

### Auto-blacklist desde webhook SendGrid

`SendgridEventProcessor` inserta en `notification_blacklist` en la misma transacción que el audit cuando recibe:
- `bounce` con `type=bounce` → `source=hard_bounce`
- `dropped` → `source=dropped`
- `spamreport` → `source=spamreport`

Soft bounces (`type=blocked`) y `deferred` solo generan audit, no bloquean.

### UI admin

`/admin/blacklist` (HTTP Basic auth, mismas envvars que `/admin/audits`):
- Listado paginado con filtros por `recipient`, `scope`, `target`, `source`.
- Alta manual (form) — registra con `source=admin_ui`.
- Remoción (`DELETE`) — atómica: crea audit `blacklist_removed` con `notification_type=_blacklist_removed_` y `metadata = {blacklist_id, scope, target, removed_by, reason}` antes de borrar.

Ver `.design-logs/ADL-010-blacklist-pre-rules-evaluation.md` para el rationale completo.

## Tareas Rake

| Comando | Descripción |
|---------|-------------|
| `bin/rails worker:run[batch_size,sleep_interval]` | Despacha jobs de `dispatch_queue` (email) |
| `bin/rails webhook_worker:run[batch_size,sleep_interval]` | Procesa eventos pendientes de `webhook_events` |
| `bin/rails "digest_scheduler:run[batch_size,sleep_interval]"` | Consolida items de `pending_digests` vencidos en 1 envío por grupo |
| `bin/rails partitions:rotate` | Crea la partición del próximo mes y dropea las más viejas que `AUDIT_RETENTION_MONTHS` |

## Para integradores

Ver [docs/integrators-guide.md](docs/integrators-guide.md) para elegir la ventana de idempotencia, cuándo pasar `context_id`, y qué casos no cubre la Central.
