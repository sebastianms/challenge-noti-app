# Feature Specification: Blacklist + bounces automáticos

**Feature Branch**: `005-blacklist-bounces`
**Created**: 2026-05-11
**Status**: Draft

## Resumen

Mecanismo de **opt-out duro**: destinatarios marcados en `notification_blacklist` nunca reciben envíos del scope bloqueado. Tres fuentes alimentan la blacklist: (1) admin/compliance manual, (2) hard bounces / dropped / spamreport del webhook de SendGrid, (3) consola Rails. La evaluación ocurre **antes** del motor de reglas — la blacklist es un veto incondicional.

Phase 6 del roadmap. Cumple R8 ("opt-outs y bounces").

## Clarifications

### Session 2026-05-11

- Eventos de SendGrid que auto-blacklistean: `bounce` (type=bounce / hard), `dropped`, `spamreport`. Soft bounces (`deferred`) NO blacklistean — se reintentan normalmente.
- Vigencia: permanente hasta remoción manual. Sin `expires_at` en MVP.
- Modelo de scope: tabla única con `scope ∈ {global, type, channel}` + `target` nullable. UNIQUE `(recipient_canonical, scope, target)`.

---

## User Scenarios & Testing

### User Story 1 - Compliance/admin agrega destinatario manualmente a blacklist (Priority: P1)

Una persona de compliance recibe un pedido de "deja de enviarle todo a este usuario". Desde la consola Rails crea una fila en blacklist con `scope=global`. El siguiente envío a ese destinatario, sea del tipo que sea, queda filtrado con motivo `blacklisted`.

**Why this priority**: requisito de compliance — sin esto, la Central no puede operar legalmente para usuarios que ejercieron derecho de oposición.

**Independent Test**: con la app corriendo, `NotificationBlacklist.create!(recipient_canonical: "x@y.com", scope: "global")`. Luego `FooNotification.send("x@y.com")` → resultado `:filtered` (o equivalente), fila en `notification_audit` con `status=filtered`, `metadata.reason="blacklisted"`, sin INSERT en `dispatch_queue`.

**Acceptance Scenarios**:

1. **Given** destinatario A está en blacklist con `scope=global`, **When** cualquier `*.send(A)` ocurre, **Then** queda auditado como `filtered` con reason `blacklisted` y no se encola.
2. **Given** destinatario A está en blacklist con `scope=type, target=birthday`, **When** `BirthdayNotification.send(A)` ocurre, **Then** queda filtrado; **When** `MfaNotification.send(A)` ocurre, **Then** se procesa normalmente.
3. **Given** destinatario A está en blacklist con `scope=channel, target=email`, **When** se intenta despachar por email, **Then** queda filtrado; otros canales (a futuro, ej. SMS) no se ven afectados.

---

### User Story 2 - Hard bounce auto-bloquea al destinatario (Priority: P1)

SendGrid envía un evento `bounce` con `type=bounce` (hard) al webhook. El sistema agrega automáticamente al destinatario a blacklist con `scope=channel, target=email, source=hard_bounce`. Cualquier envío posterior por email a ese destinatario queda filtrado.

**Why this priority**: sin esto, hard bounces reintentan eternamente y dañan la reputación del dominio remitente con SendGrid.

**Independent Test**: enviar webhook con `[{event: "bounce", type: "bounce", email: "fail@x.com", ...}]` firmado correctamente. Tras procesamiento (`WebhookEventWorker`), verificar fila en `notification_blacklist` con `recipient_canonical="fail@x.com"`, `scope="channel"`, `target="email"`, `source="hard_bounce"`. Siguiente `EmailChannel.deliver` al destinatario → filtrado.

**Acceptance Scenarios**:

1. **Given** webhook recibe evento `bounce` con `type=bounce`, **When** `WebhookEventWorker.process` lo procesa, **Then** existe fila en blacklist con `source=hard_bounce` en ≤ 30 s desde la recepción del webhook.
2. **Given** webhook recibe evento `dropped`, **When** se procesa, **Then** ídem con `source=dropped`.
3. **Given** webhook recibe evento `spamreport`, **When** se procesa, **Then** ídem con `source=spamreport`.
4. **Given** webhook recibe evento `bounce` con `type=blocked` (soft) o evento `deferred`, **When** se procesa, **Then** NO se crea fila en blacklist (solo audit de bounce normal).
5. **Given** ya existe fila en blacklist para `(recipient, channel, email)`, **When** llega otro hard bounce del mismo destinatario, **Then** la inserción es idempotente (ON CONFLICT DO NOTHING).

---

### User Story 3 - Listado y remoción de blacklist desde UI admin (Priority: P2)

Soporte/compliance necesita ver quiénes están en blacklist, por qué, y poder remover una entrada (ej. usuario reactivó cuenta, falso positivo). Extensión de `/admin/audits` con una vista `/admin/blacklist` con filtros (`scope`, `source`, `recipient`) y acción de remoción con audit trail.

**Why this priority**: bloqueante para operación día a día — sin esto, cada remoción requiere acceso a consola Rails.

**Independent Test**: `GET /admin/blacklist` muestra filas existentes. Filtros funcionales. `DELETE /admin/blacklist/:id` (vía form) remueve la fila y deja audit `blacklist_removed` con metadata `{removed_by, reason}`.

**Acceptance Scenarios**:

1. **Given** hay 50 filas en blacklist, **When** soporte abre `/admin/blacklist?scope=channel&target=email`, **Then** ve solo las que matchean, paginadas (cap 50 por página).
2. **Given** un usuario quiere ser reactivado, **When** admin remueve su fila desde la UI con motivo "usuario reactivó cuenta", **Then** la fila se borra y queda registro de la remoción (quién, cuándo, motivo).
3. **Given** admin intenta acceder sin HTTP Basic auth, **When** hace `GET /admin/blacklist`, **Then** recibe 401.

---

### Edge Cases

- ¿Qué pasa si llega un envío para un destinatario antes de que el webhook de hard bounce previo termine de procesarse? → race tolerable: el envío sale, eventualmente bouncea, blacklist se actualiza para el siguiente.
- ¿Qué pasa si `scope=global` y `scope=channel, target=email` coexisten para el mismo destinatario? → cualquiera de las dos filtra, OR lógico. Idempotente — ambas pueden coexistir sin conflicto.
- ¿Qué pasa si el webhook trae un evento con email malformado? → log de warning, no se crea blacklist (canonicalización falla con valor `nil`).
- ¿Qué pasa si el `notification_type` no existe en `notification_rules` pero hay blacklist `scope=type, target=<ese tipo>`? → la blacklist gana — se filtra antes de evaluar reglas.
- ¿Qué pasa si admin remueve una entrada de blacklist y al segundo siguiente vuelve a llegar un hard bounce del mismo destinatario? → se vuelve a insertar (idempotencia ON CONFLICT permite reinserción tras delete).

---

## Requirements

### Functional Requirements

- **FR-001**: El sistema MUST persistir entradas en `notification_blacklist` con `recipient_canonical`, `scope ∈ {global, type, channel}`, `target` (NULL si scope=global), `source ∈ {manual, hard_bounce, dropped, spamreport, admin_ui}`, `reason` (texto libre), `created_at`.
- **FR-002**: El sistema MUST imponer UNIQUE `(recipient_canonical, scope, target)` para evitar duplicados.
- **FR-003**: El sistema MUST evaluar la blacklist **antes** del motor de reglas. Si matchea cualquiera de las tres dimensiones (global, type, channel), el evento queda `filtered` con `metadata.reason="blacklisted"` y `metadata.blacklist_id` para trazabilidad.
- **FR-004**: El sistema MUST registrar en `notification_audit` cada filtrado por blacklist con `status=filtered`, `source=internal`, `notification_type`, `metadata` con la entrada de blacklist que disparó el veto.
- **FR-005**: El sistema MUST procesar eventos de webhook de SendGrid de tipos `bounce` (con `type=bounce` permanente), `dropped` y `spamreport`, insertando automáticamente una fila en blacklist con `scope=channel, target=email` y `source` correspondiente al evento.
- **FR-006**: El sistema MUST ignorar para blacklist los eventos de tipo `deferred` y `bounce` con `type=blocked` (soft bounces) — solo se registran como audit normal.
- **FR-007**: La inserción automática desde webhook MUST ser idempotente (`ON CONFLICT (recipient_canonical, scope, target) DO NOTHING`).
- **FR-008**: El sistema MUST exponer `GET /admin/blacklist` con filtros por `scope`, `target`, `source`, `recipient` y paginación (cap 50 por página). Protegido por HTTP Basic auth (reutilizar `AUDIT_BASIC_AUTH_USER/PASSWORD`).
- **FR-009**: El sistema MUST exponer `DELETE /admin/blacklist/:id` (vía form POST con `_method=delete`). La eliminación MUST registrar un audit con metadata `{removed_by, reason}` para trazabilidad.
- **FR-010**: El sistema MUST permitir CRUD desde consola Rails (`NotificationBlacklist.create!/destroy!`) como interfaz primaria para compliance.
- **FR-011**: La canonicalización del `recipient_canonical` MUST reutilizar la lógica existente de `RecipientNormalizer` (lowercase + trim) para garantizar matching consistente con audits y reglas.

### Key Entities

- **NotificationBlacklist**: representa una entrada de opt-out. Atributos: `id`, `recipient_canonical` (string, no NULL), `scope` (enum), `target` (string nullable, requerido si scope ≠ global), `source` (enum), `reason` (text), `created_at`. Constraint CHECK: `(scope='global' AND target IS NULL) OR (scope IN ('type','channel') AND target IS NOT NULL)`.

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: Un destinatario agregado manualmente a blacklist con `scope=global` recibe 0 envíos en cualquier tipo, verificado por ausencia de filas en `dispatch_queue` y presencia de `notification_audit` con `status=filtered, reason=blacklisted`.
- **SC-002**: Un hard bounce procesado por el webhook se refleja en blacklist en **≤ 30 segundos** desde la recepción HTTP (latencia incluye persistencia en `webhook_events` + procesamiento async por `WebhookEventWorker`).
- **SC-003**: Soporte responde "remover a Juan de blacklist" en **≤ 60 segundos** usando solo la UI `/admin/blacklist`, sin acceso a consola Rails.
- **SC-004**: 100% de hard bounces (`bounce` permanente + `dropped` + `spamreport`) generan fila en blacklist; 0% de soft bounces (`deferred`, `bounce` blocked) lo hacen — medido sobre suite de tests.
- **SC-005**: La evaluación de blacklist agrega **≤ 5 ms p95** a la latencia de ingesta (cubierto por índice `(recipient_canonical, scope)` y query única `WHERE recipient_canonical = ? AND (scope='global' OR (scope='type' AND target=?) OR (scope='channel' AND target=?))`).
- **SC-006**: Cobertura de línea ≥ 95% en `app/central/decisioning/blacklist_evaluator.rb` y el ramal de blacklist del `WebhookEventWorker`.

---

## Assumptions

- La canonicalización de email actual (lowercase + trim) es suficiente. Plus-aliasing (`user+tag@x.com`) NO se normaliza — `user+a@x.com` y `user+b@x.com` son destinatarios distintos a efectos de blacklist (consistente con reglas actuales).
- El webhook de SendGrid ya está activo (feature 003); esta feature solo agrega un step adicional en el procesamiento del `WebhookEventWorker`.
- La UI usa el mismo layout/auth que `/admin/audits` (Hotwire server-rendered, HTTP Basic auth). No se construye SSO ni roles — Phase 7 los introduce.
- "Channel" como scope solo aplica hoy a `email` (único canal activo). El diseño soporta futuros canales sin migración.
- Para MVP no hay TTL ni soft-delete: remoción es DELETE físico. Si el destinatario vuelve a bouncear, vuelve a insertarse vía webhook.
- El audit de remoción se persiste en `notification_audit` con un `notification_type` sintético `_blacklist_removed_` y `correlation_id` generado para el evento de remoción. **Alternativa considerada**: tabla `blacklist_audit` dedicada — descartada por agregar superficie de schema para un caso de uso de baja frecuencia.

---

## Out of Scope

- TTL / expiración automática de entradas (no requerido para MVP).
- Bulk import/export de blacklist (CSV) — Phase 8 lo cubre.
- Sincronización con sistemas externos de unsubscribe (CRM, ESP) — fuera del alcance de la Central.
- Plus-aliasing canonicalization (sería breaking change para `RecipientNormalizer`).
- SSO + roles para `/admin/blacklist` — Phase 7.
- Whitelist / overrides (forzar envío pese a blacklist) — anti-patrón para compliance.
