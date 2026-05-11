# Roadmap — Central de Notificaciones

**Estado**: En progreso · **Actualizado**: 2026-05-11

Cada fase es un **shippable slice**: deja la plataforma en un estado funcional y demostrable. El orden respeta dependencias (no se puede auditar lo que no se envía; no se puede filtrar lo que no se decide).

---

## Phase 1 — Setup & Constitución  `[DONE]`

- [x] `specs/mission.md`
- [x] `specs/tech-stack.md`
- [x] `specs/roadmap.md`
- [x] Bootstrap del proyecto Rails 8.1 + Postgres 17 + RSpec + RuboCop + GitHub Actions
- [x] Esqueleto de carpetas (`app/notifications`, `app/central/...`, `app/admin`)

**DoD**: `bundle exec rspec` corre vacío en verde, CI verde en PR inicial.

---

## Phase 2 — Foundational: AbstractNotification + Idempotencia (R1, R4)  `[DONE]`

> Sin esta capa nada más se sostiene: define el contrato público y garantiza que ningún evento duplicado avance.

- [x] Tabla `notification_events` (particionamiento por `idempotency_window_ts`, ver ADL-001 y ADL-002)
- [x] `AbstractNotification` con `title`, `body`, `digest_template`, `send`
- [x] `Central::Ingestion::EventBuilder` + cálculo de `idempotency_hash` (SHA256, ventana de tiempo configurable)
- [x] `INSERT … ON CONFLICT DO NOTHING` y resultado tipado (`:created` / `:duplicate`)
- [x] Tests: idempotencia bajo concurrencia (threads paralelos creando el mismo evento → 1 fila).

**DoD**: `FooNotification.send("a@b.com")` crea exactamente una fila en `notification_events`; segunda invocación en la misma ventana no crea otra; cobertura ≥ 90% en módulo de ingesta.

---

## Phase 3 — Email dispatch: broker + canal + auditoría (R2, R3, R7)  `[DONE]`

> El equipo de Producto puede demostrar que un equipo integra una notificación nueva en < 1 hora y que el correo llega.

- [x] Tabla `dispatch_queue` (priority, status, backoff, SKIP LOCKED index parcial)
- [x] Tabla `notification_audit` particionada por mes + partición inicial (ver ADL-003: FK omitida por limitación de tablas particionadas)
- [x] `Enqueuer` — INSERT atómico en `dispatch_queue` + audit `enqueued` dentro de la transacción de ingesta
- [x] `Worker` — `process_batch` con `FOR UPDATE SKIP LOCKED` + `CLOCK_TIMESTAMP()` (ADL-004), backoff 1m/5m/25m, DLQ tras MAX_ATTEMPTS (ADL-005)
- [x] `ChannelStrategy` (interfaz) + `ChannelRegistry` (auto-registro en carga de archivo)
- [x] `EmailChannel` + `SendgridAdapter` vía `Net::HTTP`: classifica 2xx/4xx/5xx → `:delivered`/`PermanentError`/`TransientError`
- [x] `correlation_id` propagado como header HTTP `X-Correlation-ID` **y** como `custom_args` en el payload JSON (persiste en webhooks de SendGrid)
- [x] Tests end-to-end: `spec/integration/email_dispatch_spec.rb` — happy path, idempotencia, X-Correlation-ID
- [x] `bin/rails worker:run[batch_size,sleep_interval]` para foreground
- [x] ADL-004 (CLOCK_TIMESTAMP), ADL-005 (SKIP LOCKED), ADL-006 (WebMock)
- [x] Coverage badge commiteado al repo desde CI

**DoD**: `BirthdayNotification.send("a@b.com")` → job en `dispatch_queue` → `Worker.process_batch` → status `done`, audits `[enqueued, dispatched, delivered]`; agregar un canal nuevo no requiere cambiar `AbstractNotification` ni `EventBuilder`.

---

## Phase 4 — Auditoría consultable (R6) [DONE]

> Soporte puede responder "¿por qué Juan no recibió X?" en segundos.

Implementado en feature [003-audit-query](003-audit-query/):

- [x] `PartitionManager.new(table:, retention_months:).rotate` — crea partición del próximo mes, dropea las más viejas que `AUDIT_RETENTION_MONTHS` con safety guardrail de 3 meses. Rake: `partitions:rotate`.
- [x] `AuditSearch.new(...).call` con dos modos: por `correlation_id` (timeline ASC) o filtros combinables (`recipient`, `status`, `source`, `from`, `to`, `page`, `per_page` cap 50) con `Result` paginado.
- [x] Endpoint Hotwire `/admin/audits` protegido con HTTP Basic (`AUDIT_BASIC_AUTH_USER` / `AUDIT_BASIC_AUTH_PASSWORD`). Form de filtros + tabla + paginación.
- [x] Webhook async `POST /webhooks/sendgrid` con verificación Ed25519 (ver [ADL-007](../.design-logs/ADL-007-ed25519-sendgrid-webhook-signature.md)). Persiste batch en `webhook_events`, `WebhookEventWorker` lo procesa con `FOR UPDATE SKIP LOCKED` y traduce `delivered/bounce/dropped/deferred/spamreport` → `NotificationAudit` con `source = sendgrid_webhook`.

**Esquema agregado**: columnas `source` (CHECK internal/sendgrid_webhook, default internal) y `recipient_canonical` (nullable) en `notification_audit` + tabla `webhook_events`. Cobertura suite: 100%.

---

## Phase 5 — User Story 3: Motor de reglas + cache (R5)

> Stakeholders ajustan frecuencia/canales/agrupación sin redeploy.

- [ ] Tabla `notification_rules` (tipo, canales habilitados, max_per_day, cooldown, digest, priority)
- [ ] `Central::Decisioning::RulesEngine` + `Decision` value object (`:dispatch | :digest | :filter_rule`)
- [ ] Cache con `Rails.cache` (`:memory_store`, TTL 5 min) + invalidación al guardar regla
- [ ] Pipeline integrado: ingesta → decisión → broker (con audit en cada paso)
- [ ] `pending_digests` + `Central::Broker::DigestScheduler` (worker periódico que fusiona items por ventana)

**DoD**: cambiar la regla de `WelcomeNotification` desde la consola Rails (max_per_day 3 → 1) se aplica en ≤ 5 min sin reiniciar workers; envíos extras quedan auditados con motivo `rate_limited`.

---

## Phase 6 — User Story 4: Blacklist + bounces (R8)

> Compliance y soporte controlan opt-outs; los hard bounces no reintentan eternamente.

- [ ] Tabla `notification_blacklist` (`scope`, `target`, `recipient_id`, `reason`, `source`)
- [ ] `Central::Decisioning::BlacklistEvaluator` (consulta antes de evaluar reglas)
- [ ] `Webhooks::SendgridBouncesController` con validación HMAC
- [ ] Hard bounce → INSERT en blacklist con `source=hard_bounce`
- [ ] CRUD básico de blacklist (consola + endpoints internos)

**DoD**: destinatario en blacklist nunca recibe envíos del scope bloqueado; auditado con motivo `blacklisted`; un hard bounce de Sendgrid se refleja en blacklist en < 30 s.

---

## Phase 7 — User Story 5: UI Admin — Dashboard + Reglas (R5 visible)

> Primera entrega visible al stakeholder. Cierra el loop "configurar sin código".

- [ ] Layout admin con SSO + roles (`admin`, `product`, `support`, `engineering`)
- [ ] **Dashboard**: volumen por tipo/canal, tasa de filtrado, queue depth, DLQ size, error rate
- [ ] **Gestión de reglas**: lista editable con preview, validaciones, audit trail de cambios

**DoD**: un usuario con rol `product` modifica una regla desde la UI y el cambio se refleja en métricas del dashboard.

---

## Phase 8 — User Story 6: UI Admin — Auditoría + Blacklist (R6, R8 visibles)

> Soporte y compliance operan sin pedirle ayuda a ingeniería.

- [ ] **Auditoría y búsqueda**: filtros + timeline por envío + payload + regla aplicada
- [ ] **Gestión de blacklist**: tabla con filtros, alta manual, baja con audit trail, exportación CSV

**DoD**: soporte responde una consulta real ("¿por qué Juan no recibió MFA?") en < 30 s usando solo la UI.

---

## Phase 9 — User Story 7: UI Admin — Templates + DLQ (operaciones)

> Operaciones y editorial cierran el set de capacidades.

- [ ] **Editor de templates**: preview de `title + body` y `digest_template`, lista de variables disponibles
- [ ] **Operaciones / DLQ**: items agrupados por motivo, reintento individual y masivo, descarte con motivo

**DoD**: tras simular un outage de Sendgrid (5xx forzado), operaciones evacúa la DLQ con un reintento masivo desde la UI.

---

## Phase 10 — Polish: Observabilidad, performance & hardening

- [ ] Métricas APM/CloudWatch + alarmas (queue_depth, dlq_size, 5xx, 429, bounce_rate)
- [ ] Carga de prueba: 140 rps sostenidos por 1 hora sin degradación de p95
- [ ] Brakeman + bundle-audit en CI
- [ ] Documentación developer-facing: "Cómo crear una notificación nueva en < 1 hora"
- [ ] Runbook operacional (DLQ, bounce spikes, Sendgrid down)

**DoD**: SLOs de `mission.md` verificados; runbook revisado por SRE; documentación entregada al equipo de plataforma.

---

## Fuera de roadmap (Roadmap evolutivo, post-entrega)

- Migración a Kafka/SQS (cuando volumen supere ~500 rps sostenidos)
- Extracción a microservicio dedicado de Notificaciones
- Rate limiter proactivo coordinado entre workers (R-06)
- Soporte de zonas horarias múltiples en presentación (R-07)
- Canales adicionales: SMS, Push, WhatsApp, Slack (la arquitectura ya los soporta vía Strategy)
