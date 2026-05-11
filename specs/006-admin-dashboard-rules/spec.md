# Feature Specification: UI Admin — Dashboard + Reglas

**Feature Branch**: `006-admin-dashboard-rules`
**Created**: 2026-05-11
**Status**: Draft
**Roadmap Phase**: 7

## Overview

Primera entrega visible al stakeholder de la Central. Cierra el loop "configurar sin código": un usuario con rol `product` puede modificar una regla de notificación desde el navegador y ver el efecto reflejado en el dashboard de la misma UI. Establece además la base de autenticación + autorización que reutilizarán Phase 8 (auditoría/blacklist) y Phase 9 (templates/DLQ).

---

## User Scenarios & Testing

### User Story 1 — Acceso autenticado con roles (Priority: P1)

Un administrador de plataforma inicia sesión con email + contraseña y, según su rol, ve solo las secciones a las que tiene permiso. Los roles disponibles son `admin`, `product`, `support`, `engineering`. La sesión persiste y se cierra con un botón "Cerrar sesión".

**Why this priority**: Sin auth + roles, no hay ninguna sección admin "visible al stakeholder" defendible. Las vistas existentes (`/admin/audits`, `/admin/blacklist`) hoy usan HTTP Basic con una sola credencial; eso no escala a 4 roles ni a un demo público.

**Independent Test**: Crear un usuario con rol `product`, loguearse en `/admin/login`, verificar que ve "Dashboard" y "Reglas" pero NO "Auditoría" (que llegará en Phase 8). Logout limpia la sesión.

**Acceptance Scenarios**:
1. **Given** un usuario válido en `admin_users` con rol `product`, **When** se loguea en `/admin/login`, **Then** es redirigido al dashboard y ve solo las secciones permitidas para `product`.
2. **Given** un usuario con rol `support`, **When** intenta entrar a `/admin/rules`, **Then** recibe 403 con mensaje "No tienes permisos para esta sección".
3. **Given** una sesión activa, **When** el usuario hace click en "Cerrar sesión", **Then** la cookie se invalida y `/admin/dashboard` redirige a `/admin/login`.
4. **Given** 5 intentos fallidos de login en 10 min, **When** se reintenta, **Then** el sistema bloquea el login con un mensaje genérico (no revela si el email existe).

---

### User Story 2 — Dashboard de salud operativa (Priority: P1)

Un usuario con rol `admin`, `product` o `engineering` abre `/admin/dashboard` y ve cuatro KPIs en una sola pantalla, calculados sobre las últimas 24 horas (excepto queue depth, que es en vivo):

1. **Volumen por tipo/canal** — gráfico de barras horizontal: tipo de notificación × canal con conteo de envíos.
2. **Tasa de filtrado por motivo** — pie chart o tabla: % de eventos con `status=filtered` agrupados por `metadata.reason` (`blacklisted`, `rate_limited`, `cooldown`, `disabled`, etc.).
3. **Queue depth + DLQ size** — dos números grandes en vivo: `dispatch_queue` pendientes y items en DLQ.
4. **Error rate por canal** — % de audits con `status=failed` sobre el total de envíos por canal, ventana 24h.

**Why this priority**: Es lo que el stakeholder mira primero. Cierra la promesa del roadmap ("primera entrega visible") y permite verificar el efecto de cambiar reglas en US3 sin abrir la base de datos.

**Independent Test**: Generar 50 envíos sintéticos (mix de delivered/failed/filtered), entrar a `/admin/dashboard` y verificar que los 4 KPIs reflejan los números esperados. La página debe cargar en < 2s con esa cardinalidad.

**Acceptance Scenarios**:
1. **Given** envíos en `notification_audit` de los últimos 7 días, **When** entro al dashboard, **Then** veo los 4 KPIs solo de las últimas 24h.
2. **Given** la cola de despacho con 12 jobs pendientes y 3 en DLQ, **When** refresco el dashboard, **Then** los contadores reflejan 12 y 3 (no cacheado más de 30s).
3. **Given** un usuario con rol `support`, **When** intenta entrar al dashboard, **Then** ve solo el dashboard sin el menú lateral de reglas.
4. **Given** sin datos en las últimas 24h, **When** entro al dashboard, **Then** veo cada KPI con un estado vacío legible ("Sin envíos en las últimas 24h"), no errores ni cero ambiguo.

---

### User Story 3 — Gestión de reglas con audit trail (Priority: P1)

Un usuario con rol `admin` o `product` accede a `/admin/rules`, ve la lista de reglas existentes con sus campos clave, y puede:

1. **Crear** una regla nueva via formulario con validaciones inline (todos los campos de `NotificationRule`).
2. **Editar** una regla existente; los cambios se persisten y disparan invalidación de cache vía callbacks ya existentes.
3. **Eliminar** una regla con confirmación.
4. **Ver historial de cambios** de una regla específica (quién, cuándo, qué campo cambió de qué valor a qué valor).

Cada operación de create/update/delete persiste una fila en `rule_changes` con `admin_user_id`, `action` (`created`/`updated`/`deleted`), `before` y `after` como JSONB, y `changed_at`.

**Why this priority**: Es la mitad operativa de la promesa de Phase 7 ("configurar sin código"). Sin esto, las reglas siguen siendo un capricho de consola Rails.

**Independent Test**: Loguearse como `product`, crear una regla para `notification_type = "birthday"` con `max_per_day = 1`, verificar que aparece en la lista, editarla a `max_per_day = 2`, ver en el historial los dos cambios con los valores antes/después correctos.

**Acceptance Scenarios**:
1. **Given** un usuario `product` en `/admin/rules/new`, **When** envía el form con `notification_type` vacío, **Then** ve el error inline "Tipo de notificación es obligatorio" sin perder el resto del form.
2. **Given** un usuario `product` edita una regla existente, **When** guarda el cambio, **Then** la próxima invocación de `RuleCache.get(type)` retorna los nuevos valores en ≤ 5 min (TTL existente) y se crea fila en `rule_changes`.
3. **Given** un usuario `support`, **When** intenta entrar a `/admin/rules`, **Then** recibe 403.
4. **Given** una regla con 3 cambios históricos, **When** entro a `/admin/rules/:id/history`, **Then** veo 3 entradas ordenadas DESC con diff campo-a-campo.
5. **Given** una regla activa con `enabled=true`, **When** la marco como `enabled=false`, **Then** el `RulesEngine` la trata como inexistente desde el próximo evento (vía invalidación de cache existente).

---

### User Story 4 — Generar data mock para demos (Priority: P2)

Un usuario con rol `admin` ve en el dashboard (y en la lista de reglas) un botón **"Generar Data Mock"**. Al presionarlo, el sistema crea un set sintético y coherente de datos (envíos, audits con mix de delivered/failed/filtered, reglas de ejemplo, items en cola y DLQ, entradas de blacklist) suficiente para que las vistas se vean "vivas" en una demo. Una segunda pulsación agrega más data sin duplicar reglas. El botón está visible por defecto y se oculta cuando la variable de entorno `ALLOW_MOCK_DATA_FEATURE=false`.

**Why this priority**: La promesa "primera entrega visible al stakeholder" se sostiene cuando el dashboard se ve poblado. En un entorno fresco (CI, sandbox del evaluador, demo en vivo) sin tráfico real, los 4 KPIs muestran estado vacío y la sección pierde fuerza narrativa. Un botón self-service evita escribir Rake tasks ad-hoc y elimina la dependencia de "tenés que correr esto antes de mostrar". P2 porque la app funciona sin él; pero sumado al MVP cambia la experiencia del primer 1 minuto del stakeholder.

**Independent Test**: En un entorno sin data, loguearse como `admin`, entrar al dashboard, presionar "Generar Data Mock", verificar que los 4 KPIs se pueblan con valores no vacíos y que `/admin/rules` muestra al menos 3 reglas de ejemplo. Setear `ALLOW_MOCK_DATA_FEATURE=false`, recargar y confirmar que el botón desaparece.

**Acceptance Scenarios**:
1. **Given** un usuario `admin` y `ALLOW_MOCK_DATA_FEATURE` unset o `=true`, **When** entra al dashboard, **Then** ve un botón "Generar Data Mock" visible.
2. **Given** un usuario `admin`, **When** presiona "Generar Data Mock" en un entorno sin datos, **Then** se crean al menos: 3 reglas de ejemplo, 50 envíos auditados con mix de status, 5 items en `dispatch_queue`, 2 en DLQ, 3 entradas de blacklist; y el dashboard refleja conteos > 0 en los 4 KPIs.
3. **Given** `ALLOW_MOCK_DATA_FEATURE=false`, **When** cualquier usuario entra al dashboard o a la lista de reglas, **Then** el botón "Generar Data Mock" NO se renderiza.
4. **Given** `ALLOW_MOCK_DATA_FEATURE=false`, **When** un usuario hace POST directo a la ruta del generador, **Then** recibe 403 (la protección no depende solo de ocultar el botón).
5. **Given** un usuario con rol distinto de `admin` y feature habilitada, **When** intenta usar el generador, **Then** recibe 403.
6. **Given** que ya se ejecutó el generador una vez, **When** se vuelve a presionar, **Then** se agregan más envíos/audits sin duplicar reglas (UPSERT por `notification_type`) ni emails de blacklist (idempotente por `(recipient_canonical, scope, target)`).

---

### Edge Cases

- **Usuario sin rol asignado** (NULL en `admin_users.role`): se trata como sin permisos; redirige a una página explicativa y no rompe.
- **Dashboard con `notification_audit` vacío**: cada KPI muestra estado vacío en vez de "0%" o NaN.
- **Edición concurrente de una regla**: dos admins editan la misma regla a la vez; gana el último que guarda. El historial muestra ambas filas. No se implementa optimistic locking en esta fase (deferido a Phase 10).
- **Cambio de rol de un usuario logueado**: aplica en la siguiente request (no requiere logout forzado).
- **Tipo de notificación inexistente en código**: una regla puede crearse para un `notification_type` que aún no tiene clase Ruby asociada. Se permite (es válido pre-deployar la regla); el RulesEngine ya tolera esto.

---

## Requirements

### Functional Requirements

- **FR-001**: El sistema MUST autenticar administradores con email + contraseña usando Devise.
- **FR-002**: El sistema MUST persistir admin_users con campos `id`, `email` (UNIQUE), `encrypted_password`, `role` (CHECK IN admin/product/support/engineering), `created_at`, `updated_at`.
- **FR-003**: El sistema MUST autorizar por rol antes de servir cualquier vista admin. Roles → secciones permitidas:
  - `admin`: todas (dashboard, rules)
  - `product`: dashboard, rules
  - `engineering`: dashboard
  - `support`: dashboard (solo lectura)
- **FR-004**: El sistema MUST bloquear login tras 5 intentos fallidos en 10 minutos (lockable de Devise).
- **FR-005**: El sistema MUST exponer `/admin/dashboard` con 4 KPIs descritos en US2.
- **FR-006**: El sistema MUST calcular los KPIs sobre los últimos 24 hours (excepto queue depth/DLQ que es en vivo) con queries directas a `notification_audit` + `dispatch_queue`.
- **FR-007**: El sistema MUST cachear los KPIs de volumen, tasa de filtrado y error rate por 30 segundos (`Rails.cache`) para soportar refresh frecuente sin pegar la DB.
- **FR-008**: El sistema MUST exponer CRUD completo de `notification_rules` en `/admin/rules` (index, new, create, edit, update, destroy).
- **FR-009**: El sistema MUST validar inline todos los campos de la regla (notification_type único, channels array o NULL, max_per_day ≥ 0, cooldown_seconds ≥ 0, digest_window_seconds ≥ 0, priority IN critical/standard/bulk).
- **FR-010**: El sistema MUST persistir cada cambio de regla en `rule_changes` (action, before JSONB, after JSONB, admin_user_id, changed_at) dentro de la misma transacción que el cambio en `notification_rules`.
- **FR-011**: El sistema MUST exponer `/admin/rules/:id/history` con las filas de `rule_changes` ordenadas DESC.
- **FR-012**: El sistema MUST reusar el `RuleCache` existente (callbacks `after_save`/`after_destroy` ya invalidan; este feature no los toca).
- **FR-013**: El sistema MUST registrar logout via DELETE `/admin/logout` y limpiar la sesión.
- **FR-014**: El sistema MUST NOT exponer información sensible (qué emails existen) en errores de login: mensaje genérico "Email o contraseña inválidos".
- **FR-015**: El sistema MUST exponer un endpoint protegido `POST /admin/mock_data` que genera un set sintético coherente de datos para demos: reglas (idempotente por `notification_type`), envíos auditados con mix de `delivered/failed/filtered`, items en `dispatch_queue` (algunos pending, algunos en DLQ) y entradas de `notification_blacklist` (idempotente por unique key).
- **FR-016**: El sistema MUST renderizar un botón "Generar Data Mock" en `/admin/dashboard` y `/admin/rules` sólo cuando `ALLOW_MOCK_DATA_FEATURE` no sea `false` (default = visible).
- **FR-017**: El sistema MUST rechazar el POST a `/admin/mock_data` con 403 cuando `ALLOW_MOCK_DATA_FEATURE=false`, incluso si el usuario está autenticado como `admin`. La protección no depende del estado del botón en la vista.
- **FR-018**: El sistema MUST restringir `/admin/mock_data` al rol `admin`; otros roles reciben 403.

### Key Entities

- **AdminUser**: representa un operador con acceso al panel. Atributos: id, email, encrypted_password, role, sign_in_count, current_sign_in_at, failed_attempts, locked_at.
- **RuleChange**: registro auditable de cambios sobre `notification_rules`. Atributos: id, notification_rule_id (nullable on delete), admin_user_id, action (created/updated/deleted), before (jsonb), after (jsonb), changed_at.

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: Un usuario `product` modifica una regla desde la UI y el efecto se observa en el dashboard de la misma UI en ≤ 5 minutos (TTL de cache de reglas) sin reiniciar workers.
- **SC-002**: El dashboard carga las 4 métricas en ≤ 2 segundos con 10k filas en `notification_audit` (window 24h).
- **SC-003**: El sistema bloquea el acceso a `/admin/rules` para usuarios con rol `support` en el 100% de los intentos (verificado por test de autorización).
- **SC-004**: Cada operación de create/update/delete sobre una regla deja exactamente 1 fila en `rule_changes` con `admin_user_id` correcto, verificable en `/admin/rules/:id/history` en ≤ 1 click desde la lista.
- **SC-005**: La cobertura de los módulos nuevos (`AdminUser`, `RuleChange`, controllers `Admin::SessionsController`, `Admin::DashboardController`, `Admin::RulesController`) es ≥ 95% y la suite global se mantiene ≥ 99%.
- **SC-006**: Login tras 5 intentos fallidos queda bloqueado por al menos 10 minutos (test de Devise lockable).
- **SC-007**: En un entorno sin datos, un único click en "Generar Data Mock" deja los 4 KPIs del dashboard con valores > 0 y al menos 3 reglas listadas en `/admin/rules`, en ≤ 3 segundos.
- **SC-008**: Con `ALLOW_MOCK_DATA_FEATURE=false`, el botón no se renderiza en ninguna vista y un POST directo al endpoint responde 403 en el 100% de los intentos (verificado por test).

---

## Assumptions

- Devise es aceptable como dependencia (alineado con el approach pragmático del MVP; alternativa de OmniAuth queda para evolución futura).
- El dashboard usa Hotwire/Turbo (consistente con `/admin/audits` y `/admin/blacklist`); las gráficas se renderizan con Chartkick + Chart.js (sin SPA).
- Los queries de KPIs son aceptables sin materialización (Phase 10 evaluará vistas materializadas si el volumen crece).
- `admin_users` se sembrará vía seeds o Rake task; no hay flujo de signup público (los admins se crean offline).
- La sesión de Devise usa cookies httpOnly + secure en producción.
- No hay multi-tenancy: un único conjunto de admins controla toda la Central.
- El logout es global (no por dispositivo) — suficiente para esta fase.
- El generador de mock data es seguro de ejecutar contra una DB con datos reales (no trunca; usa upsert/insert idempotente). Aun así, la recomendación operativa es desactivarlo en producción vía `ALLOW_MOCK_DATA_FEATURE=false`.
- El default del flag es "visible" porque el contexto de este proyecto es un challenge demostrable; en un despliegue corporativo el default debería invertirse vía configuración de entorno.

---

## Out of Scope (defer to later phases)

- **Phase 8**: vistas `/admin/audits` (ya existe pero con HTTP Basic; migrará a Devise) y `/admin/blacklist` (ídem) + auditoría con filtros avanzados.
- **Phase 9**: editor de templates y operación de DLQ.
- **Phase 10**: optimistic locking en edición concurrente de reglas, vistas materializadas para dashboard, métricas APM.
- **Roadmap evolutivo**: SSO con Google/Okta.
