# Feature Specification: Auditoría Consultable

**Feature Branch**: `003-audit-query`
**Created**: 2026-05-11
**Status**: Draft

## Contexto

La tabla `notification_audit` y sus transiciones básicas (`enqueued → dispatched → delivered / failed`) quedaron implementadas en la Phase 3 (Email Dispatch). Esta feature agrega la **capa de consulta y operación**: soporte puede responder preguntas sobre envíos individuales en segundos, el sistema mantiene las particiones bajo control automáticamente, y los eventos de entrega/bounce que SendGrid notifica vía webhook se registran de forma automática en el historial.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Búsqueda de historial por correlation ID (Priority: P1)

Un agente de soporte recibe el reclamo: "Juan dice que no recibió su email de cumpleaños del 10 de mayo." El agente busca por el `correlation_id` que el equipo de ingeniería le proporciona desde los logs del integrador y obtiene el timeline completo del envío: cuándo fue ingresado, encolado, despachado y cuál fue el resultado final.

**Why this priority**: Es el caso de uso principal que justifica toda la infraestructura de auditoría. Sin búsqueda rápida por correlation ID, la tabla existe pero es inútil operacionalmente.

**Independent Test**: Dado un conjunto de auditorías en distintos estados, buscar por un `correlation_id` específico retorna exactamente las entradas de ese envío, ordenadas cronológicamente.

**Acceptance Scenarios**:
1. **Given** que existe un envío con `correlation_id = "uuid-abc"` con tres entradas de audit (enqueued, dispatched, delivered), **When** soporte busca por ese `correlation_id`, **Then** el sistema retorna las tres entradas en orden cronológico ascendente con todos sus campos (status, channel, timestamp, metadata).
2. **Given** que no existe ningún envío con `correlation_id = "uuid-xyz"`, **When** soporte busca por ese ID, **Then** el sistema retorna una lista vacía (no un error).
3. **Given** que existen auditorías de múltiples envíos, **When** soporte busca por el `correlation_id` del envío A, **Then** solo retorna las entradas del envío A.

---

### User Story 2 — Búsqueda por destinatario, estado y rango de fechas (Priority: P1)

Un agente de soporte quiere ver todos los envíos fallidos del último mes para el email `juan@example.com`, para identificar si hay un patrón de fallos para ese destinatario.

**Why this priority**: La búsqueda por correlation ID resuelve el caso individual; la búsqueda por filtros múltiples resuelve el análisis de patrones y la investigación sin un ID previo.

**Independent Test**: Dado un dataset de auditorías variadas, los filtros por `recipient_canonical`, `status` y rango de fechas retornan exactamente las entradas que cumplen todos los criterios simultáneamente.

**Acceptance Scenarios**:
1. **Given** múltiples auditorías de envíos a `juan@example.com` y a otros destinatarios, **When** soporte filtra por `recipient_canonical = "juan@example.com"`, **Then** solo retorna entradas de ese destinatario.
2. **Given** auditorías con distintos estados (enqueued, delivered, failed), **When** soporte filtra por `status = "failed"`, **Then** solo retorna entradas con estado `failed`.
3. **Given** auditorías en distintas fechas, **When** soporte filtra por rango `from: 2026-05-01, to: 2026-05-31`, **Then** solo retorna entradas dentro de ese rango.
4. **Given** los tres filtros aplicados simultáneamente, **When** soporte busca, **Then** el sistema aplica los tres como condición AND.
5. **Given** más de 50 resultados, **When** soporte realiza la búsqueda, **Then** los resultados se presentan paginados (página de hasta 50 ítems) con indicador de total y navegación.

---

### User Story 3 — Registro de eventos de entrega/bounce de SendGrid (Priority: P1)

SendGrid notifica al sistema (vía webhook) que un email fue entregado, rebotó (soft o hard bounce), o fue marcado como spam. El sistema registra automáticamente ese evento en `notification_audit`, usando el `correlation_id` que viaja en el payload del webhook para cruzar con el envío original.

**Why this priority**: Sin este webhook, el estado final de entrega en `notification_audit` es solo lo que el sistema supo en el momento del despacho (202 de la API), no si el email realmente llegó a la bandeja de entrada. Los bounces también son la fuente de datos para auto-blacklisting (Phase 6).

**Independent Test**: Simular un POST al endpoint de webhook con payload de bounce de SendGrid y verificar que se crea una nueva entrada en `notification_audit` con el status correcto, sin modificar las entradas anteriores del mismo `correlation_id`.

**Acceptance Scenarios**:
1. **Given** un envío previo con `correlation_id = "uuid-abc"` en estado `delivered`, **When** SendGrid envía un webhook de tipo `delivered` con `custom_args.correlation_id = "uuid-abc"`, **Then** el sistema agrega una entrada de audit con status `sg_delivered` y el payload completo del evento.
2. **Given** un envío previo, **When** SendGrid envía un webhook de tipo `bounce` (hard bounce), **Then** el sistema agrega una entrada con status `sg_bounced` e incluye el tipo de bounce en el metadata.
3. **Given** un webhook de SendGrid con `correlation_id` desconocido (sin matching en notification_audit), **When** el sistema lo recibe, **Then** lo registra de todas formas como una entrada huérfana con el correlation_id recibido (no descarta silenciosamente).
4. **Given** un POST al endpoint de webhook con payload mal formado (sin `correlation_id`), **When** el sistema lo recibe, **Then** retorna HTTP 400 y no crea ninguna entrada de audit.
5. **Given** un POST al endpoint de webhook con firma HMAC inválida, **When** el sistema lo recibe, **Then** retorna HTTP 401 y rechaza el evento sin procesarlo.

---

### User Story 4 — Gestión automática de particiones mensuales (Priority: P2)

El sistema crea automáticamente la partición del mes siguiente antes de que empiece ese mes, y elimina particiones con más de N meses de antigüedad para mantener el volumen de la tabla bajo control.

**Why this priority**: Sin gestión de particiones, la tabla eventualmente crece sin límite o falla al intentar insertar en el primer día del mes siguiente si la partición no existe. Es infraestructura operacional que no bloquea las funcionalidades de consulta.

**Independent Test**: Dado que existen las particiones de los últimos 3 meses, ejecutar el `PartitionManager` crea la del mes siguiente y elimina las que superan el límite de retención configurado.

**Acceptance Scenarios**:
1. **Given** que hoy es el último día del mes y la partición del mes siguiente no existe, **When** se ejecuta el PartitionManager, **Then** la partición del mes siguiente queda creada y disponible para recibir inserciones.
2. **Given** que existen particiones de 7 meses atrás y la retención configurada es 6 meses, **When** se ejecuta el PartitionManager, **Then** la partición de 7 meses atrás es eliminada.
3. **Given** que la partición del mes siguiente ya existe, **When** se ejecuta el PartitionManager, **Then** no falla ni duplica la partición (idempotente).
4. **Given** que se ejecuta el PartitionManager y hay datos en una partición a eliminar, **When** se intenta eliminar esa partición, **Then** el sistema alerta (log de warning) pero no elimina particiones con datos recientes (< 3 meses), independientemente de la configuración de retención.

---

### Edge Cases

- ¿Qué pasa si SendGrid envía el mismo evento webhook dos veces (reentrega)? → El sistema registra ambas entradas (append-only), sin deduplicación a nivel webhook.
- ¿Qué pasa si la búsqueda por fechas cruza el límite de partición (e.g., noviembre + diciembre)? → La consulta debe funcionar correctamente cruzando múltiples particiones.
- ¿Qué pasa si la partición del mes actual no existe en el momento de un INSERT? → La partición default de `notification_audit` captura el insert y el PartitionManager la crea en el próximo ciclo.
- ¿Qué pasa si el webhook llega antes de que el job en dispatch_queue sea procesado? → Es posible en teoría (carrera de SendGrid vs. Worker), el sistema registra el evento de todas formas sin validar la secuencia.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sistema DEBE permitir buscar entradas de `notification_audit` filtrando por `correlation_id` exacto.
- **FR-002**: El sistema DEBE permitir buscar entradas de `notification_audit` filtrando por `recipient_canonical`, `status` y rango de fechas (individualmente o combinados).
- **FR-003**: Los resultados de búsqueda DEBEN estar paginados con un máximo de 50 ítems por página.
- **FR-004**: El sistema DEBE exponer un endpoint HTTP para recibir eventos de webhook de SendGrid.
- **FR-005**: El endpoint de webhook DEBE validar la firma HMAC de SendGrid antes de procesar el payload; rechazar con 401 si la firma es inválida.
- **FR-006**: El endpoint de webhook DEBE extraer el `correlation_id` del campo `custom_args` del payload y registrar una entrada en `notification_audit`.
- **FR-007**: El endpoint de webhook DEBE retornar 400 si el payload no contiene `correlation_id`.
- **FR-008**: El sistema DEBE incluir un `PartitionManager` capaz de crear la partición del mes siguiente.
- **FR-009**: El `PartitionManager` DEBE eliminar particiones con antigüedad mayor a N meses (configurable, default 6).
- **FR-010**: El `PartitionManager` DEBE ser idempotente: ejecutarlo múltiples veces no genera errores ni duplicados.
- **FR-011**: El `PartitionManager` DEBE proteger particiones con datos de menos de 3 meses de antigüedad, independientemente de la configuración de retención.

### Key Entities

- **NotificationAudit**: Registro inmutable de cada transición de estado de un envío. Campos relevantes: `correlation_id`, `status`, `channel`, `payload` (JSONB), `metadata` (JSONB), `created_at`. Ya existe desde Phase 3.
- **SendGridEvent**: Evento recibido vía webhook. Campos: `event` (tipo: delivered, bounce, spamreport), `email` (destinatario), `timestamp`, `custom_args.correlation_id`, `type` (bounce type: hard/soft).

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Dado 1.000 envíos sintéticos distribuidos en el mes, la búsqueda por `correlation_id` retorna el timeline completo en menos de 200 ms en el percentil 95.
- **SC-002**: Un evento de bounce recibido vía webhook de SendGrid queda registrado en `notification_audit` en menos de 30 segundos desde su recepción.
- **SC-003**: La búsqueda por `recipient_canonical` con 10.000 registros en la tabla retorna la primera página en menos de 500 ms.
- **SC-004**: El `PartitionManager` crea la partición del mes siguiente y elimina las antiguas en una sola ejecución sin errores, verificable en menos de 5 segundos de runtime.
- **SC-005**: Cobertura de tests ≥ 90% en todos los módulos nuevos de esta feature.

---

## Assumptions

- La autenticación del webhook de SendGrid se realiza con validación de firma HMAC usando la clave provista en la variable de entorno `SENDGRID_WEBHOOK_SECRET`. En entornos de test, la validación puede deshabilitarse o usar una clave fija.
- El endpoint Hotwire de búsqueda es una vista HTML simple con un formulario de filtros y una tabla de resultados — no una API REST JSON. La UI completa (con layout admin, roles, SSO) se construye en Phases 7–8.
- Los tipos de evento de SendGrid relevantes para esta fase son: `delivered`, `bounce`, `spamreport`. Otros tipos (`open`, `click`) se ignoran o registran sin procesamiento especial.
- La retención de particiones es configurable vía variable de entorno `AUDIT_RETENTION_MONTHS` con default de 6 meses.
- El `PartitionManager` se invoca manualmente desde un rake task o consola en esta fase. La ejecución periódica automática (cron) se integra en Phase 10.
- El campo `recipient_canonical` en `notification_audit` se puebla copiando el `recipient_id` normalizado del `notification_event` asociado vía `correlation_id`.
