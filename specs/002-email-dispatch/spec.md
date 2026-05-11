# Feature Specification: Email Dispatch — Broker + Channel Strategy

**Feature Branch**: `002-email-dispatch`
**Created**: 2026-05-10
**Status**: Draft

---

## User Scenarios & Testing

### User Story 1 — Despacho de email funcional de extremo a extremo (P1)

Un equipo integrador define una notificación y la envía con una línea. El email llega al destinatario a través de Sendgrid sin que el integrador elija proveedor, configure reintentos ni gestione la cola.

**Por qué P1**: es la garantía central de la plataforma — "una sola forma de enviar produce un correo verificable". Sin esto, el valor de la Central no se puede demostrar.

**Test independiente**: `WelcomeNotification.send("ana@empresa.com")` con el sandbox activo produce una fila en `dispatch_queue` con `status = done` y un registro en `notification_audit` con `status = delivered` — verificable en test de integración sin llamar a la API real de Sendgrid.

**Acceptance Scenarios**:

1. **Given** una notificación con `title` y `body` definidos, **When** se invoca `send("recipient@example.com")`, **Then** se crea una fila en `dispatch_queue` con `priority = standard` y `status = pending`.
2. **Given** una fila `pending` en `dispatch_queue`, **When** el Worker procesa el job, **Then** llama al `EmailChannel` con el `correlation_id` del evento original, y la fila pasa a `status = done`.
3. **Given** el Worker llama al `EmailChannel` con éxito, **Then** se registra una transición `dispatched → delivered` en `notification_audit` con el `correlation_id` y el nombre del canal (`email`).
4. **Given** el adapter de Sendgrid está en modo sandbox (test env), **Then** el email se "envía" sin llamar a la API real; el resultado es determinista e idéntico en CI.

---

### User Story 2 — Reintentos con backoff y Dead-Letter Queue (P1)

Cuando Sendgrid responde con un error transitorio (5xx, timeout), el Worker reintenta con backoff exponencial. Tras tres reintentos fallidos el job pasa a Dead-Letter Queue (`status = failed`) sin perderse.

**Por qué P1**: sin retry confiable, cualquier flicker de red o throttling de Sendgrid produce pérdida de notificaciones — inaceptable para la garantía de entrega.

**Test independiente**: con el adapter configurado para devolver error en los primeros tres intentos, el job debe moverse por `attempts = 1, 2, 3` antes de caer en `status = failed` con `failed_reason` documentado. El cuarto intento no ocurre.

**Acceptance Scenarios**:

1. **Given** un job `pending` en `dispatch_queue`, **When** el adapter responde con error 5xx, **Then** el Worker incrementa `attempts` en 1, calcula `next_attempt_at` según el schedule de backoff, y devuelve el job a `pending`.
2. **Given** un job con `attempts = 1`, **Then** `next_attempt_at` está aproximadamente 1 minuto en el futuro; con `attempts = 2` → ~5 minutos; con `attempts = 3` → ~25 minutos.
3. **Given** un job con `attempts = 3` falla de nuevo, **Then** el job pasa a `status = failed` (DLQ); no se hacen más intentos automáticos.
4. **Given** el Worker procesa un job, **Then** lo marca como `in_flight` (SKIP LOCKED) antes de llamar al adapter — otros workers no lo procesan en paralelo.

---

### User Story 3 — Correlation ID propagado al proveedor (P2)

El `correlation_id` generado en la ingesta viaja como header HTTP `X-Correlation-ID` en cada llamada a Sendgrid. Cuando Sendgrid registra el evento, ese ID aparece en sus logs, permitiendo cruzar incidentes.

**Por qué P2**: trazabilidad cross-sistema es necesaria para soporte, pero no bloquea la entrega básica.

**Test independiente**: el `SendgridAdapter` recibe el `correlation_id` del evento y lo incluye en los headers de la petición HTTP; verificable sin llamar a la API real (stub de HTTP con VCR o WebMock).

**Acceptance Scenarios**:

1. **Given** un evento con `correlation_id = "uuid-123"`, **When** el adapter construye la petición a Sendgrid, **Then** incluye el header `X-Correlation-ID: uuid-123`.
2. **Given** un job reintentado (segundo intento), **Then** el header `X-Correlation-ID` es el mismo del evento original, no uno nuevo.

---

### Edge Cases

- ¿Qué pasa si el recipient es un `user_id` (no email)? El `RecipientNormalizer` ya existe — el `EmailChannel` debe rechazar jobs cuyo `recipient_id` no contenga `@` con `failed_reason = "no_email_address"`.
- ¿Qué pasa si el `EmailChannel` es llamado con `title` o `body` nulos? El adapter debe levantar `ArgumentError`; el Worker lo captura y pasa el job a DLQ inmediatamente (sin reintentos — error permanente, no transitorio).
- ¿Qué pasa si el Worker muere a mitad de un job `in_flight`? El job queda con `locked_at` seteado; un proceso de recovery (o reinicio del worker) puede reclamar jobs `in_flight` con `locked_at` > N minutos (considerado en el diseño, implementación diferida a Phase 10).
- ¿Qué pasa si el `dispatch_queue` tiene miles de jobs acumulados? El Worker usa `LIMIT N` en el `SELECT … FOR UPDATE SKIP LOCKED` — siempre procesa un batch fijo independiente del tamaño de la cola.

---

## Requirements

### Functional Requirements

- **FR-001**: El sistema DEBE crear una fila en `dispatch_queue` con `status = pending` cada vez que `EventBuilder.build` retorna un resultado `:created`.
- **FR-002**: El sistema DEBE leer jobs de `dispatch_queue` usando `SELECT … FOR UPDATE SKIP LOCKED` para soportar múltiples workers concurrentes sin race conditions.
- **FR-003**: El sistema DEBE reintentar jobs fallidos con el schedule de backoff: 1 min → 5 min → 25 min → DLQ (máximo 3 reintentos).
- **FR-004**: El sistema DEBE propagar el `correlation_id` del evento al header HTTP `X-Correlation-ID` en cada llamada al adapter de Sendgrid.
- **FR-005**: El `EmailChannel` DEBE mapear `title` → `subject` y `body` → `html_content` al construir el payload de Sendgrid.
- **FR-006**: El sistema DEBE registrar una transición de auditoría en `notification_audit` para cada cambio de estado: `enqueued`, `dispatched`, `delivered`, `failed`.
- **FR-007**: El adapter de Sendgrid DEBE ser intercambiable sin modificar `EmailChannel` (Strategy + inyección de dependencia). La integración con Sendgrid se testea via **WebMock/VCR** — se stubbea la llamada HTTP al nivel de red; no existe una clase `SandboxAdapter` separada.
- **FR-008**: Agregar un canal nuevo (ej. `LogChannel`) DEBE requerir solo registrar el adapter en `ChannelRegistry` — sin modificar `AbstractNotification` ni `EventBuilder`.

### Key Entities

- **`dispatch_queue`**: Job de despacho pendiente. Atributos: `event_id`, `priority` (`critical|standard|bulk`), `status` (`pending|in_flight|done|failed`), `attempts`, `next_attempt_at`, `locked_at`, `failed_reason`.
- **`DispatchJob`**: value object que representa un job leído del queue (no persiste solo).
- **`Central::Broker::Enqueuer`**: crea la fila en `dispatch_queue` a partir de un `SendResult` creado.
- **`Central::Broker::Worker`**: loop `SKIP LOCKED`, llama al canal, gestiona backoff.
- **`Central::Channels::ChannelStrategy`**: interfaz con `deliver(event, recipient)` y `channel_name`.
- **`Central::Channels::ChannelRegistry`**: mapea símbolo → instancia de `ChannelStrategy`.
- **`Central::Channels::EmailChannel`**: implementa `ChannelStrategy`; delega al adapter configurado.
- **`Central::Channels::SendgridAdapter`**: construye y envía (o simula) la petición HTTP a Sendgrid.
- **`notification_audit`**: log inmutable de transiciones por `correlation_id`.

---

## Success Criteria

- **SC-001**: Un equipo integrador puede demostrar que `FooNotification.send("a@b.com")` produce un correo verificable (en sandbox) sin configurar nada más que la clase de notificación.
- **SC-002**: Un job de despacho fallido con 3 errores consecutivos aterriza en DLQ con razón documentada — sin pérdida silenciosa.
- **SC-003**: Agregar `LogChannel` (que solo escribe en el log) requiere crear un archivo y registrarlo — sin tocar `AbstractNotification`, `EventBuilder`, ni `EmailChannel`.
- **SC-004**: El `correlation_id` del evento aparece en el header `X-Correlation-ID` de la petición a Sendgrid — verificable en test sin llamar a la API real.
- **SC-005**: La suite RSpec corre en verde con cobertura ≥ 90% en `app/central/broker/` y `app/central/channels/`.

---

## Assumptions

- El `RecipientNormalizer` ya existe y se reutiliza para distinguir emails de `user_id`; `EmailChannel` solo acepta recipients con `@`.
- La tabla `notification_audit` se crea **ya particionada por día** (`PARTITION BY RANGE (created_at)`) desde esta fase, con la partición del día actual como partición inicial. Phase 4 agrega el `AuditLogger` completo y la búsqueda, pero la estructura de almacenamiento queda definida aquí.
- La tabla `dispatch_queue` no se particiona por `priority` en esta fase (el roadmap lo menciona pero Phase 3 solo necesita el índice `(status, priority, next_attempt_at)` para el SKIP LOCKED eficiente).
- El Worker expone un método `start` que corre un **loop continuo** en un thread con `sleep` entre ciclos. En tests se usa `Worker.new.process_batch(batch_size: N)` para un único ciclo determinista (sin sleep). El método `start` es el punto de entrada para producción (rake task o proceso supervisado).
- `SENDGRID_API_KEY` está disponible en el entorno solo cuando `Rails.env.production?`. En test, las llamadas HTTP a Sendgrid se interceptan con **WebMock** (o cassettes VCR) — sin clave real necesaria.
- La prioridad por defecto para `AbstractNotification.send` es `:standard`; los integradores pueden sobrescribirla con `priority: :critical`.
- El enqueuing ocurre dentro de `EventBuilder.build`: si el resultado es `:created`, `EventBuilder` llama a `Enqueuer.enqueue` **dentro de la misma transacción** antes de retornar el `SendResult`. El llamador (`AbstractNotification`) no necesita conocer `Enqueuer`. Si la transacción hace rollback, ninguna de las dos filas persiste.
