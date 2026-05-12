# Feature Specification: UI Admin — Auditoría + Blacklist

**Feature Branch**: `007-admin-ui-audit-blacklist`
**Created**: 2026-05-12
**Status**: Draft

## User Scenarios & Testing

### User Story 1 — Soporte responde "¿por qué Juan no recibió X?" (Priority: P1)

Una persona de soporte recibe un ticket: "el cliente Juan no recibió el correo de cumpleaños del 10 de mayo". Necesita encontrar el evento en segundos, ver la línea de tiempo completa (enqueued → dispatched → delivered/filtered/failed) y entender el motivo si no se entregó.

**Why this priority**: Es el caso de uso #1 del módulo de auditoría. Sin esto, soporte escala todo a ingeniería.

**Independent Test**: Soporte filtra por `recipient=juan@example.com` + `from=2026-05-10`; encuentra 1 fila; hace click y ve la timeline con cada estado, el payload del evento y la regla aplicada (si hubo una).

**Acceptance Scenarios**:
1. **Given** un envío auditado con 3 filas (enqueued/dispatched/delivered), **When** soporte abre la vista de detalle por `correlation_id`, **Then** ve los 3 eventos en orden ascendente con timestamp y status.
2. **Given** un envío filtrado por regla (reason=`rate_limited`, rule_id=42), **When** abre el detalle, **Then** ve "Filtrado: rate_limited (regla #42)" con link a la regla actual.
3. **Given** filtros `reason=blacklisted` aplicados, **When** soporte ejecuta búsqueda, **Then** la tabla muestra solo audits filtrados por blacklist.

---

### User Story 2 — Compliance gestiona blacklist con audit trail y export (Priority: P1)

Compliance recibe una solicitud GDPR de borrado/bloqueo. Necesita agregar el email a blacklist con motivo, confirmar el alta y poder exportar la lista filtrada por scope/source para auditoría externa.

**Why this priority**: Bloquea la operación de compliance, que hoy depende de Rails console.

**Independent Test**: admin/support agrega un email a blacklist global con razón "GDPR ticket #123"; aparece en la tabla; exporta CSV filtrado por `source=admin_ui` y obtiene un archivo con las altas manuales.

**Acceptance Scenarios**:
1. **Given** un usuario con rol `support`, **When** completa el form de alta con recipient + scope=global + reason, **Then** la fila aparece en la tabla con `source=admin_ui` y la sesión queda auditada (created_by).
2. **Given** una entrada existente, **When** soporte la borra desde la UI, **Then** se crea un audit `blacklist_removed` con metadata.removed_by = email del admin (no "console").
3. **Given** filtros aplicados (recipient + scope), **When** click en "Exportar CSV", **Then** descarga un archivo `blacklist-YYYYMMDDHHMM.csv` con esas filas.

---

### User Story 3 — Migración a Devise (Priority: P1)

Las rutas `/admin/audits` y `/admin/blacklist` hoy están con HTTP Basic. Phase 7 introdujo Devise + roles para todo lo demás. Hay que unificar.

**Why this priority**: Sin esto, la UI tiene dos sistemas de auth inconsistentes y el `removed_by` queda como "console" en vez del email del admin.

**Independent Test**: usuario no autenticado a `/admin/audits` → redirect a `/admin/login` (no prompt HTTP Basic). Engineering accede a audits ✓ pero no puede crear/borrar en blacklist (403).

**Acceptance Scenarios**:
1. **Given** un usuario no autenticado, **When** entra a `/admin/audits` o `/admin/blacklist`, **Then** es redirigido a `/admin/login`.
2. **Given** rol `engineering`, **When** intenta `POST /admin/blacklist`, **Then** recibe 403.
3. **Given** rol `support`, **When** elimina una entrada de blacklist, **Then** la audit `blacklist_removed` registra `metadata.removed_by = support@noti-central.local`.

---

### Edge Cases

- CSV export con 0 resultados → archivo con solo header, status 200.
- CSV export grande (> 10k filas): se hace stream con `ActionController::Live` o `find_each`, sin cargar todo en memoria.
- Filtro `rule_id` con valor inválido (texto en vez de int) → se ignora silenciosamente.
- Detalle por `correlation_id` con un solo audit (caso filtered) → timeline muestra esa fila como evento terminal.
- Usuario hace logout en otra pestaña mientras está en `/admin/audits` → próxima request redirige a login.

## Requirements

### Functional Requirements

- **FR-001**: La autenticación de `/admin/audits` y `/admin/blacklist` DEBE usar Devise (sesión + cookie), reemplazando HTTP Basic.
- **FR-002**: Los permisos por rol DEBEN ser: audits → admin/product/support/engineering; blacklist (lectura) → admin/product/support/engineering; blacklist (crear/borrar) → admin/support.
- **FR-003**: La vista de detalle de audit (`/admin/audits/<correlation_id>` o similar) DEBE mostrar timeline cronológico ASC, payload del evento de la primera fila, y si hubo `reason`/`rule_id`, link a la regla (si todavía existe).
- **FR-004**: El index de `/admin/audits` DEBE aceptar filtros adicionales `reason` y `rule_id` además de los actuales (correlation_id, recipient, status, source, from, to).
- **FR-005**: `/admin/blacklist` DEBE incluir un botón "Exportar CSV" que descargue las filas que matchean los filtros actuales con headers `id,recipient_canonical,scope,target,source,reason,created_at`.
- **FR-006**: `/admin/audits` DEBE incluir un botón "Exportar CSV" con headers `correlation_id,status,channel,source,notification_type,recipient_canonical,reason,rule_id,created_at`.
- **FR-007**: Al eliminar una entrada de blacklist desde la UI con Devise activo, el audit `blacklist_removed` DEBE registrar `metadata.removed_by = current_admin_user.email`.
- **FR-008**: Tests de request DEBEN cubrir: redirect-to-login, 403 por rol, CSV export, timeline render, filtros nuevos.

### Key Entities

- **NotificationAudit** (existente): consultado vía `AuditSearch`. Se agrega filtro por `metadata->>'reason'` y `metadata->>'rule_id'`.
- **NotificationBlacklist** (existente): sin cambios de schema.
- **AdminUser** (existente): `current_admin_user.email` se usa para `removed_by`.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Un usuario con rol `support` resuelve un caso real (busca por recipient + fecha → abre timeline → identifica motivo de no-entrega) en < 30 segundos sin asistencia de ingeniería.
- **SC-002**: CSV export de hasta 10 000 filas se completa en < 5 segundos sin exceder 100 MB de RAM en el servidor.
- **SC-003**: 100% de las acciones de blacklist (crear/borrar) realizadas desde la UI quedan asociadas al `email` del admin que las ejecutó (no "console", no NULL).
- **SC-004**: 0 rutas admin operativas siguen usando HTTP Basic después de esta feature.
- **SC-005**: Cobertura ≥ 95% en los módulos modificados (audits_controller, blacklist_controller, AuditSearch si se extiende, helpers de CSV).

## Assumptions

- Stream CSV con `enumerator + ActionController::Live` está OK para evitar cargar 10k filas en memoria; alternativamente `find_each` con `send_data` si el volumen real es bajo.
- El detalle de audit reutiliza el modo `correlation_id` ya existente en `AuditSearch`; solo se agrega una acción `show` que renderiza diferente.
- "removed_by = email" reemplaza el heurístico actual de decodificar HTTP Basic header; cuando se ejecute desde consola (sin sesión), seguirá siendo "console".
- Los filtros `reason` y `rule_id` se aplican vía `metadata @> '{...}'` (JSONB containment) o coerción explícita.
