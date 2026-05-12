# Feature Specification: UI Admin — Templates + DLQ

**Feature Branch**: `008-admin-templates-dlq`
**Created**: 2026-05-12
**Status**: Draft

---

## User Scenarios & Testing

### User Story 1 — Editor de templates con preview (Priority: P1)

Una persona de Producto o Marketing necesita ajustar el copy de una notificación (ej. cambiar "¡Feliz cumpleaños!" por "Hoy es tu día 🎉") sin esperar un deploy. Entra al panel admin, abre la lista de templates, edita el `title`, `body` y/o `digest_template`, revisa el preview renderizado con valores de ejemplo, y guarda. El próximo envío usa el copy nuevo.

**Why this priority**: Cierra el loop "configurar sin código" iniciado en Phase 5 (motor de reglas) y Phase 7 (UI reglas). Sin esto, cada cambio de copy es un PR + deploy + ventana de release.

**Independent Test**: Crear override para `birthday`, llamar `BirthdayNotification.send(...)`, verificar que el `dispatch_queue.payload` usa el nuevo copy y no el del archivo Ruby.

**Acceptance Scenarios**:
1. **Given** un admin/product logueado, **When** edita el title de `birthday` y guarda, **Then** el preview muestra el copy renderizado con el contexto de ejemplo y la base de datos persiste el override.
2. **Given** un override existente, **When** se invoca `BirthdayNotification.send(...)`, **Then** el `Enqueuer` usa el copy de la DB en lugar del definido en el archivo Ruby.
3. **Given** una notificación sin override, **When** se invoca su `.send`, **Then** se usa el copy del archivo Ruby (compatibilidad hacia atrás).
4. **Given** el preview, **When** falta una variable del contexto en el template, **Then** se muestra advertencia "variable `:name` no resolvió" sin romper la página.

---

### User Story 2 — Operaciones gestiona la DLQ (Priority: P1)

Tras un outage de SendGrid, operaciones / engineering encuentra cientos de items en `dispatch_queue` con status `dead`. Entra a `/admin/dlq`, ve los items agrupados por `last_error_class` o `reason`, expande un grupo, reintenta uno individual para confirmar que SendGrid volvió, y luego hace "reintentar todos los `Net::OpenTimeout`" (cap 500). Los items vuelven a `pending` con `attempts=0` y se procesan en el siguiente batch del Worker.

**Why this priority**: Sin UI de DLQ, evacuar requiere consola Rails. En un incidente con cientos de items, el costo operacional es alto y el tiempo de recuperación se mide en horas.

**Independent Test**: Insertar 5 items `dead` con distinto `last_error`, abrir `/admin/dlq`, reintentar 1 individual, confirmar que pasa a `pending`; luego reintento masivo del grupo restante.

**Acceptance Scenarios**:
1. **Given** items con status `dead` en `dispatch_queue`, **When** un admin/engineering entra a `/admin/dlq`, **Then** ve la lista agrupada por causa con counts.
2. **Given** un item dead, **When** ejecuta "Reintentar", **Then** el item pasa a `status=pending`, `attempts=0`, `available_at=NOW()` y se genera audit `dlq_retried` con `retried_by=email`.
3. **Given** un grupo de 50 items con mismo motivo, **When** ejecuta "Reintentar todos", **Then** los 50 vuelven a `pending` en una transacción, audit único `dlq_bulk_retried` con `count=50` y `reason_filter`.
4. **Given** un grupo de 600 items, **When** ejecuta "Reintentar todos", **Then** procesa solo los primeros 500 e informa "se reintentaron 500 de 600; ejecutá de nuevo para los restantes".
5. **Given** un item irrecuperable (recipient inválido), **When** ejecuta "Descartar" con motivo, **Then** el item queda `status=discarded`, audit `dlq_discarded` con `discarded_by=email` y `reason`.
6. **Given** un usuario `product` o `support`, **When** intenta entrar a `/admin/dlq`, **Then** recibe 403.

---

### Edge Cases

- ¿Qué pasa si un override de template referencia una variable inexistente en el contexto? → Preview muestra warning, runtime renderiza string vacío (Mustache-like, no excepción).
- ¿Qué pasa si dos admins editan el mismo template simultáneamente? → Last-write-wins con `updated_at` mostrado en el form; sin locking optimista (volumen muy bajo).
- ¿Qué pasa si reintento masivo encuentra que algunos items ya cambiaron de estado (race con worker)? → `UPDATE … WHERE status='dead'` filtra; reporta count real actualizado.
- ¿Qué pasa si un template override se borra mientras hay items en `pending_digests` con snapshot? → El digest usa su snapshot; no se ve afectado (consistente con ADL-009).

---

## Requirements

### Functional Requirements

**Templates**:
- **FR-001**: El sistema MUST permitir CRUD de overrides de templates en una tabla `notification_templates` con campos `(notification_type, locale, title, body, digest_template)`.
- **FR-002**: `AbstractNotification.title/body/digest_template` MUST consultar primero el override en DB (con cache 5 min, mismo patrón que `RuleCache`) y caer al método de la subclase si no existe.
- **FR-003**: El editor MUST renderizar un preview en vivo con un contexto de ejemplo editable por el usuario.
- **FR-004**: El preview MUST detectar variables no resueltas y mostrarlas como warning sin abortar el render.
- **FR-005**: Solo roles `admin` y `product` MUST poder editar templates.

**DLQ**:
- **FR-006**: El sistema MUST exponer `/admin/dlq` listando `dispatch_queue` con `status=dead` agrupado por `last_error_class` (o equivalente extraído de `last_error`).
- **FR-007**: Cada item MUST poder reintentarse individualmente; al hacerlo, pasa a `status=pending`, `attempts=0`, `available_at=NOW()` y genera audit `dlq_retried` con `metadata.retried_by`.
- **FR-008**: El reintento masivo MUST aceptar un filtro por motivo y procesar máximo 500 items por operación en una sola transacción.
- **FR-009**: El reintento masivo MUST generar un único audit `dlq_bulk_retried` con `metadata.count` y `metadata.reason_filter`.
- **FR-010**: El descarte MUST requerir motivo no vacío, marcar `status=discarded` y generar audit `dlq_discarded` con `metadata.reason` y `metadata.discarded_by`.
- **FR-011**: Solo roles `admin` y `engineering` MUST poder acceder a `/admin/dlq` y ejecutar acciones.

### Key Entities

- **NotificationTemplate**: override editable de los textos de una notificación. Atributos: `notification_type` (FK lógica al tipo Ruby), `locale` (default `"es"`), `title`, `body`, `digest_template`, timestamps. UNIQUE `(notification_type, locale)`.
- **DispatchQueue (existente)**: nuevo `status="discarded"` permitido en CHECK constraint; nuevo audit_type `_dlq_retried_` / `_dlq_bulk_retried_` / `_dlq_discarded_`.

---

## Success Criteria

- **SC-001**: Una persona de Producto puede cambiar el title de una notificación y ver el cambio reflejado en un envío real en < 5 minutos (sin redeploy).
- **SC-002**: Tras un outage simulado que deja 200 items en DLQ con el mismo motivo, operaciones evacúa el 100% con ≤ 2 clicks ("filtrar por motivo" + "reintentar todos") en < 30 segundos.
- **SC-003**: 0 endpoints `/admin/*` siguen con HTTP Basic (heredado de Phase 8).
- **SC-004**: Cobertura de tests ≥ 90% en módulos nuevos; suite global se mantiene en verde.

---

## Assumptions

- El volumen de templates es bajo (≤ 50 tipos de notificación), por lo que cache TTL de 5 min con invalidación sincrónica es suficiente (mismo patrón que [ADL-008](../../.design-logs/ADL-008-rails-cache-rule-strategy.md)).
- El interpolation engine para templates es simple `{{key}}` (no Liquid completo, no condicionales). Variables faltantes resuelven a string vacío con warning en preview.
- DLQ no tiene SLA de retención propio; los items `discarded` se pueden purgar manualmente vía Rake en una iteración futura.
- Sin i18n real en MVP: `locale="es"` fijo, columna existe para futura extensión.
- Reintento masivo cap 500 es endurecido en el controller, no configurable por UI.
