# Feature Specification: Motor de reglas + digest + cache

**Feature Branch**: `004-rules-engine`
**Created**: 2026-05-11
**Status**: Draft

## Overview

Hoy cualquier llamada a `FooNotification.send(...)` se traduce 1:1 en un email despachado. Producto y Compliance no pueden ajustar frecuencia, agrupar, o desactivar canales sin pedirle a Ingeniería un deploy.

Esta feature introduce una capa de **decisión** entre Ingesta (capa A) y Broker (capa C). Cada evento pasa por el motor de reglas configurables (`notification_rules`), que decide:

- **Despachar inmediato** → como hoy.
- **Agrupar** → encolar en `pending_digests` para fusionar en un solo envío al cierre de la ventana.
- **Filtrar** → no despachar y dejar audit con motivo (`rate_limited`, `disabled`, `cooldown`).

Las reglas son editables desde la consola Rails (UI vendrá en Phase 7) y se cachean por 5 minutos. El cambio de una regla se refleja en el comportamiento real en ≤ 5 minutos sin reiniciar workers.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Decisión por reglas en el pipeline (Priority: P1)

Producto crea una regla para `WelcomeNotification` con `max_per_day=1, channels=[email]`. Cuando alguien dispara `WelcomeNotification.send("juan@example.com")` por segunda vez en el mismo día, la plataforma no envía email; en su lugar registra un audit con `status=filtered`, `metadata.reason=rate_limited`.

**Why this priority**: es el core de la feature; sin esto, no hay valor agregado sobre Phase 3.

**Independent Test**: crear regla con `max_per_day=1`, disparar `WelcomeNotification.send(...)` dos veces seguidas; verificar 1 fila `delivered` + 1 fila `filtered(reason=rate_limited)` en `notification_audit`.

**Acceptance Scenarios**:
1. **Given** una regla `max_per_day=3` para tipo X, **When** se disparan 5 envíos al mismo destinatario en un día, **Then** los primeros 3 se despachan y los últimos 2 quedan auditados con `reason=rate_limited`.
2. **Given** una regla con `channels=[]` (canal deshabilitado), **When** se dispara una notificación de ese tipo, **Then** se audita con `reason=disabled` sin tocar `dispatch_queue`.
3. **Given** una notificación sin regla configurada (default fallback), **When** se dispara, **Then** se despacha sin restricciones (compatibilidad hacia atrás con Phase 3).
4. **Given** una regla con `cooldown_seconds=60`, **When** se dispara dos veces seguidas en 30 s, **Then** el segundo envío queda `filtered(reason=cooldown)`.

---

### User Story 2 — Agrupar envíos (digest) (Priority: P1)

Marketing crea una regla `digest_window_seconds=3600` para `MentionNotification`. Cuando un usuario recibe 5 menciones en una hora, en lugar de 5 emails, recibe 1 solo email al final de la ventana con un resumen ("Tienes 5 nuevas menciones").

**Why this priority**: feature distinguida del producto; demuestra el valor de la capa de decisión.

**Independent Test**: configurar regla con digest_window_seconds=300; disparar 4 envíos en 1 minuto; correr `DigestScheduler.process_batch` después de 5 min; verificar 1 sola fila en `dispatch_queue` con payload de digest fusionado.

**Acceptance Scenarios**:
1. **Given** regla con `digest_window_seconds=300`, **When** se disparan 3 envíos del mismo tipo al mismo destinatario en 60 s, **Then** se crean 3 filas en `pending_digests` (no en `dispatch_queue`).
2. **Given** 3 items en `pending_digests` cuya ventana ya venció, **When** corre `DigestScheduler.process_batch`, **Then** se crea 1 fila en `dispatch_queue` con `payload` que incluye los 3 items, y los 3 `pending_digests` se marcan `consolidated`.
3. **Given** un item en `pending_digests` cuya ventana NO venció, **When** corre el scheduler, **Then** el item permanece sin tocarse.
4. **Given** la consolidación de un digest, **When** ocurre, **Then** se crea audit `digested` con metadata `{items_count: N, source_correlation_ids: [...]}`.

---

### User Story 3 — Edición de reglas en caliente (Priority: P1)

Un product manager abre la consola Rails y cambia `max_per_day` de 3 a 1 en la regla de `WelcomeNotification`. En ≤ 5 minutos, los workers aplican la nueva regla sin reinicio.

**Why this priority**: cierra el loop "configurar sin deploy" — promesa central del producto.

**Independent Test**: configurar regla con `max_per_day=3`; disparar 2 envíos (ambos pasan); actualizar la regla a `max_per_day=1`; esperar TTL del cache (5 min en prod, configurable en test); disparar 1 envío más; verificar que queda `rate_limited`.

**Acceptance Scenarios**:
1. **Given** una regla cacheada, **When** se modifica la fila en BD, **Then** dentro de 5 min el cache se invalida o expira y los próximos envíos usan la nueva regla.
2. **Given** un cache miss, **When** el motor evalúa una regla, **Then** hace 1 sola query a `notification_rules` y la cachea.
3. **Given** 10 envíos seguidos del mismo tipo, **When** se evalúan, **Then** solo 1 hit a BD por la regla (los otros 9 leen del cache).

---

### User Story 4 — Pipeline integrado con auditoría (Priority: P2)

Cada decisión queda registrada en `notification_audit` con su motivo. Soporte puede consultar "¿por qué Juan no recibió X?" y ver `filtered(reason=rate_limited)` con la regla que aplicó.

**Why this priority**: ya tenemos auditoría (Phase 4); esto solo agrega los nuevos status/reasons. Es valor incremental, no bloqueante.

**Independent Test**: disparar un envío que queda filtrado por rate limit; consultar `/admin/audits?correlation_id=...` y verificar que aparece la fila `filtered` con `metadata.reason` y `metadata.rule_id`.

**Acceptance Scenarios**:
1. **Given** un envío filtrado por reglas, **When** se consulta el audit, **Then** la fila incluye `status=filtered`, `metadata.reason` (uno de: `rate_limited`, `disabled`, `cooldown`), y `metadata.rule_id`.
2. **Given** un envío agrupado, **When** se consulta el audit del evento original, **Then** existe una fila `status=digested` con `metadata.digest_id` apuntando a la fila consolidada.

---

### Edge Cases

- **Regla eliminada mientras hay items en `pending_digests`**: los items existentes se procesan con la última configuración conocida (snapshot en la fila). Reglas futuras no aplican retroactivamente.
- **Cambio de `digest_window_seconds` con items pendientes**: los items existentes mantienen su `dispatch_at` original (no se re-calcula).
- **Race condition entre `max_per_day` y dos envíos simultáneos**: el contador se evalúa contra `notification_audit` (la fuente de verdad post-ingesta). Si ambos pasan la verificación simultáneamente, ambos se despachan; el rate limit es best-effort, no estricto (decisión documentada).
- **Notificación crítica con regla restrictiva**: las reglas se respetan incluso para tipos marcados `priority=critical`. Si Producto quiere bypass para algún tipo, debe omitir su regla o usar `max_per_day=null`.
- **TTL del cache distinto al intervalo del cron del scheduler**: el digest se procesa por `dispatch_at` (campo en la fila), no por el cache.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sistema DEBE consultar `notification_rules` antes de encolar en `dispatch_queue`. Si no hay regla para el tipo, despachar sin restricciones (compatibilidad).
- **FR-002**: El sistema DEBE soportar las decisiones `dispatch`, `digest`, `filter` y registrar cada una como audit entry con `metadata.reason`.
- **FR-003**: El sistema DEBE aplicar rate limit por destinatario canónico (`max_per_day` cuenta envíos del mismo tipo al mismo `recipient_canonical` en las últimas 24 h).
- **FR-004**: El sistema DEBE aplicar cooldown por destinatario canónico (`cooldown_seconds` desde el último envío exitoso del mismo tipo al mismo destinatario).
- **FR-005**: El sistema DEBE persistir items agrupables en `pending_digests` con un campo `dispatch_at` calculado al insertar (`now + digest_window_seconds`).
- **FR-006**: Un worker periódico (`DigestScheduler`) DEBE consolidar items en `pending_digests` cuyo `dispatch_at <= now`, agruparlos por `(notification_type, recipient_canonical)`, crear 1 fila en `dispatch_queue` con payload fusionado y marcar los originales `consolidated`.
- **FR-007**: El motor DEBE cachear reglas usando `Rails.cache` con TTL 5 min, invalidable explícitamente al modificar una regla.
- **FR-008**: Cada decisión (`dispatch`/`digest`/`filter`) DEBE persistir su `rule_id` en `notification_audit.metadata` para trazabilidad.
- **FR-009**: El sistema DEBE soportar el campo `channels` (array) en una regla; un envío de tipo con `channels=[]` se filtra con `reason=disabled`.
- **FR-010**: Si una regla se elimina, los items pendientes en `pending_digests` con esa regla SE consolidan con su snapshot (no se descartan ni quedan huérfanos).
- **FR-011**: Los workers de `DigestScheduler` DEBEN soportar concurrencia con `FOR UPDATE SKIP LOCKED` sobre `pending_digests`.

### Key Entities

- **NotificationRule**: representa la configuración de un tipo de notificación. Atributos clave: `notification_type` (único), `channels` (array de strings), `max_per_day` (int, nullable), `cooldown_seconds` (int, nullable), `digest_window_seconds` (int, nullable), `priority` (`critical|standard|bulk`), `enabled` (bool), `created_at`, `updated_at`.
- **PendingDigest**: representa un evento en cola de agrupación. Atributos: `notification_type`, `recipient_canonical`, `correlation_id`, `payload` (snapshot), `dispatch_at`, `status` (`pending|consolidated|orphaned`), `consolidated_into` (correlation_id de la fila resultante).
- **Decision**: value object retornado por el motor. Tipos: `:dispatch`, `:digest(window: N)`, `:filter(reason: ...)`. Incluye `rule_id` aplicado.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Un product manager modifica una regla en la consola y el comportamiento cambia en ≤ 5 minutos sin reiniciar workers.
- **SC-002**: Con 100 envíos seguidos del mismo tipo, el motor de reglas hace ≤ 1 hit a BD por la regla (cache hit rate ≥ 99%).
- **SC-003**: La decisión del motor (incluyendo lookup de rate limit) toma ≤ 5 ms p95 medido localmente.
- **SC-004**: Tras 100 envíos del mismo tipo a 10 destinatarios con `digest_window_seconds=60`, se generan exactamente 10 emails consolidados, uno por destinatario.
- **SC-005**: 0 envíos despachados violando una regla activa cacheada (consistencia eventual aceptada hasta 5 min tras edición).
- **SC-006**: Cobertura de tests ≥ 90% sobre `app/central/decisioning/` y `app/central/broker/digest_scheduler.rb`.

## Assumptions

- Las 3 notificaciones existentes (`PaymentFailedNotification`, etc.) NO tienen regla y siguen despachando sin límites (compatibilidad hacia atrás).
- El rate limit es best-effort, no transaccional: dos envíos simultáneos en milisegundos pueden ambos pasar la verificación (documentado en edge cases).
- El cron de `DigestScheduler` corre cada 1 minuto en producción; la latencia máxima del digest es `digest_window_seconds + 60 s`.
- HTTP Basic auth de `/admin/rules` (Phase 7 UI) reutiliza las env vars de Phase 4 (`AUDIT_BASIC_AUTH_USER` / `AUDIT_BASIC_AUTH_PASSWORD`).
- Las reglas existen para `notification_type` (no para `recipient_canonical` ni combinaciones). Reglas por destinatario son fuera de scope.
- El campo `channels` solo se valida; el routing efectivo a un canal específico (email vs SMS) sigue siendo decisión del `ChannelRegistry` (hoy solo hay email). La regla no fuerza canal nuevo; solo bloquea si está vacío.

## Clarifications

### Session 2026-05-11

- **Default sin regla**: despachar sin límites (compatibilidad hacia atrás). Crear una regla = configurar restricciones.
- **Trigger del digest**: ventana por fila (`dispatch_at` en `pending_digests`). El worker consulta `WHERE dispatch_at <= now`.
- **Scope del rate limit**: por `recipient_canonical` (no global). Requiere índice sobre `notification_audit (notification_type, recipient_canonical, created_at)` para queries eficientes.
