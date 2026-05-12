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

## Phase 5 — Motor de reglas + cache (R5) `[DONE]`

> Stakeholders ajustan frecuencia/canales/agrupación sin redeploy.

Implementado en feature [004-rules-engine](004-rules-engine/):

- [x] Tabla `notification_rules` (tipo único, channels TEXT[], max_per_day, cooldown_seconds, digest_window_seconds, priority, enabled) con constraints CHECK y UNIQUE.
- [x] `RulesEngine.decide(event:) → Decision` value object (`:dispatch | :digest | :filter`). Orden: disabled → rate_limited → cooldown → digest → dispatch. Sin regla → dispatch (compat).
- [x] `RuleCache` con `Rails.cache`, TTL 5 min, invalidación sincrónica via `after_save`/`after_destroy` (ver [ADL-008](../.design-logs/ADL-008-rails-cache-rule-strategy.md)). Cache hit rate verificado: 20 sends mismo tipo → ≤ 1 query.
- [x] Pipeline integrado: `EventBuilder` invoca `RulesEngine`; según `Decision.kind` → `Enqueuer` o `PendingDigest.create!` o audit `filtered` con `metadata.reason`/`metadata.rule_id`.
- [x] `pending_digests` con `rule_snapshot` JSONB (ver [ADL-009](../.design-logs/ADL-009-rule-snapshot-pending-digests.md)) + `DigestScheduler.process_batch` con `FOR UPDATE SKIP LOCKED` (ADL-005 reusado). Agrupa por `(notification_type, recipient_canonical)` y consolida en 1 fila en `dispatch_queue` por grupo.
- [x] Vista `/admin/audits` extendida con columnas `reason` y `rule_id`.
- [x] Rake `digest_scheduler:run[batch_size,sleep_interval]` para foreground.

**Esquema agregado**: 2 tablas nuevas (`notification_rules`, `pending_digests`) + columna `notification_type` en `notification_audit` con índice cubriente. Cobertura suite: 100%.

---

## Phase 6 — User Story 4: Blacklist + bounces (R8)  `[DONE]`

> Compliance y soporte controlan opt-outs; los hard bounces no reintentan eternamente.

- [x] Tabla `notification_blacklist` (`scope`, `target`, `recipient_canonical`, `reason`, `source`) con CHECK + UNIQUE NULLS NOT DISTINCT
- [x] `BlacklistEvaluator` con query única OR + LIMIT 1; integración pre-reglas en `EventBuilder`
- [x] `SendgridEventProcessor` extendido: hard bounce / dropped / spamreport → INSERT en blacklist en la misma transacción que el audit (idempotente via `insert_all` ON CONFLICT)
- [x] UI `/admin/blacklist` (HTTP Basic) con index filtrado, alta manual y remoción auditada (`blacklist_removed`)
- [x] ADL-010 — evaluación pre-reglas + transaccionalidad del webhook

**DoD ✅**: destinatario en blacklist nunca recibe envíos del scope bloqueado; auditado con motivo `blacklisted`; un hard bounce de Sendgrid se refleja en blacklist en < 30 s. Cobertura 100% en módulos nuevos, suite 335/335.

---

## Phase 7 — User Story 5: UI Admin — Dashboard + Reglas (R5 visible)  `[DONE]`

> Primera entrega visible al stakeholder. Cierra el loop "configurar sin código".

- [x] Layout admin con Devise + roles (`admin`, `product`, `support`, `engineering`). Login en `/admin/login`, logout, lockable (5 intentos), paranoid mode.
- [x] `RoleAuthorizer` — matriz de permisos: admin/product → dashboard+rules; engineering/support → solo dashboard; solo admin → mock_data.
- [x] **Dashboard** (`/admin/dashboard`): volumen 7 días (bar chart), tasa de filtrado (pie chart), queue depth, DLQ size, error rate por tipo. Cache 30 s en métricas históricas, queue depth en vivo.
- [x] **Gestión de reglas** (`/admin/rules`): CRUD completo con validaciones, historial de cambios campo-a-campo (`RuleChange` con before/after JSONB). Cada mutación en transacción atómica.
- [x] **Mock data** (`/admin/mock_data`): feature flag ENV `ALLOW_MOCK_DATA_FEATURE`. Genera 5 reglas, 3 entradas de blacklist, 20 audits y 5 items en cola. Idempotente para reglas/blacklist.
- [x] ADL-011 — Devise + admin_users(role) en lugar de HTTP Basic para el panel admin.

**DoD ✅**: un usuario con rol `product` modifica una regla desde la UI y el cambio se refleja en métricas del dashboard. Cobertura 100%, 457 ejemplos en verde.

---

## Phase 8 — User Story 6: UI Admin — Auditoría + Blacklist (R6, R8 visibles)  `[DONE]`

> Soporte y compliance operan sin pedirle ayuda a ingeniería.

- [x] Migración HTTP Basic → Devise en `/admin/audits` y `/admin/blacklist`; 0 endpoints admin con HTTP Basic.
- [x] `RoleAuthorizer` extendido: `audits` (todos), `blacklist_read` (todos), `blacklist_write` (admin+support).
- [x] **Auditoría y búsqueda**: filtros `reason`/`rule_id` + timeline visual por `correlation_id` (`/admin/audits/:cid`) con payload y link a regla aplicada. Export CSV (`?format=csv`).
- [x] **Gestión de blacklist**: tabla con filtros, alta manual, baja con `removed_by=email`, exportación CSV. ADL-012.
- [x] `removed_by` pasa de `"admin"` (genérico HTTP Basic) a `current_admin_user.email` (trazable).

**DoD ✅**: soporte responde una consulta real ("¿por qué Juan no recibió MFA?") en < 30 s usando solo la UI. Cobertura 100%, 500 ejemplos en verde.

---

## Phase 9 — User Story 7: UI Admin — Templates + DLQ (operaciones)  `[DONE]`

> Operaciones y editorial cierran el set de capacidades.

- [x] **Editor de templates**: `notification_templates` DB-backed con override sobre `AbstractNotification`. Interpolación `{{variable}}` propia (no Liquid). Cache 5 min + invalidación sincrónica. Preview en `/admin/templates/:id/edit`.
- [x] **Operaciones / DLQ**: `/admin/dlq` lista `dispatch_queue WHERE status='failed'` agrupado por clase de error. Reintento individual, masivo (cap 500, transaccional, audit consolidado) y descarte con motivo. Roles: admin + engineering.
- [x] ADL-013 (template override resolver), ADL-014 (DLQ bulk retry cap).

**DoD ✅**: tras un outage simulado, operaciones evacúa la DLQ con reintento masivo desde la UI en < 30 s. Copy de notificación actualizable desde el panel sin redeploy. Cobertura 100%, 586 ejemplos en verde.

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
