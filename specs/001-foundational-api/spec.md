# Feature Specification: Foundational Notification API & Idempotencia

**Feature Branch**: `001-foundational-api`
**Created**: 2026-05-10
**Status**: Draft

## Clarifications

### Session 2026-05-10

- **Q1 — Identidad del destinatario**: el primer argumento de `send` puede ser un **email** o un **user_id interno** indistintamente. La plataforma detecta el tipo (heurística: presencia de `@`) y lo normaliza a una forma canónica para el hash. La consolidación de equivalencias `user_id ↔ email` se hace en el canal de despacho (feature posterior), **no** en la ingesta. Esto habilita multi-canal sin forzar cambios al integrador.
- **Q2 — Tipo de ventana de idempotencia**: **tumbling window** con truncamiento al inicio de la ventana en UTC (`window_ts = floor(now_utc, idempotency_window)`). Trade-off aceptado: dos invocaciones legítimas separadas por pocos segundos *podrían* caer en ventanas distintas en el borde y producir dos eventos. Beneficio: la unicidad se resuelve completamente con `UNIQUE constraint` + `ON CONFLICT DO NOTHING` en una sola operación atómica, sin lookups previos. La ventana default de 1 min se considera adecuada porque los duplicados accidentales reales (doble clic, reintento de cliente) ocurren en sub-segundo, muy adentro de la ventana.
- **Q3 — Identificador del tipo de notificación**: cada subclase puede declarar opcionalmente un identificador estable (ej. `notification_type :invoice_paid`). Si no se declara, se usa el FQN de la clase normalizado (ej. `billing/invoice_paid_notification`). Esto preserva la idempotencia histórica frente a refactors de namespace cuando el integrador lo declara explícitamente, y no agrega fricción cuando no le importa.
- **Q4 — Comportamiento sin `context:`**: cuando el integrador no provee `context:`, el slot de contexto en el `idempotency_hash` se rellena con una **constante explícita** (`"no_context"`). Esto colapsa dos invocaciones equivalentes al mismo destinatario en la misma ventana, lo cual cubre el 95% de los casos reales (reintentos, dobles disparos en código). Cuando el integrador necesita explícitamente que dos invocaciones idénticas-en-input se traten como distintas, debe pasar un `context:` que las diferencie.

  **Casos NO cubiertos por esta capa** (responsabilidad del llamador):
  - **Rage clicks / dobles clicks de UI**: dos invocaciones desde el frontend separadas por menos de la ventana se colapsarán en una; pero el patrón correcto para esto **no** es depender de la idempotencia de la plataforma sino aplicar protección anti-rage-click en el frontend (debounce del botón, deshabilitar tras primer click, throttle del endpoint que dispara la notificación). La idempotencia de la plataforma es una **red de seguridad**, no la primera línea de defensa.
  - **Eventos genuinamente distintos sin contexto**: si un equipo dispara dos `BirthdayNotification` legítimamente distintas al mismo destinatario en menos de un minuto sin `context:`, la segunda se considerará duplicada. Solución: declarar un `context:` discriminante.

## Overview

Esta feature establece el **contrato público** que los 25+ equipos usarán para definir y disparar notificaciones, y garantiza que ningún evento duplicado avance por el pipeline. Es la capa de cimientos: sin ella, no existe la promesa de "un archivo, una línea para enviar" ni la promesa de "0% duplicados".

Cubre los requisitos **R1** (contrato unificado) y **R4** (idempotencia) del documento de misión. Aún **no envía correos**: solo captura, deduplica y registra eventos. El despacho real de email es responsabilidad de la siguiente feature.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Definir una notificación nueva en un solo archivo (Priority: P1)

Un ingeniero de uno de los 25+ equipos necesita notificar a los usuarios cuando ocurre algún evento de su dominio (ej. cumpleaños, comentario nuevo, recordatorio). Hoy debe tocar varios archivos con nombres que tienen que coincidir, y un typo le cuesta horas. Queremos que pueda definir el tipo en **un solo archivo**, declarando un título y un cuerpo, y que la plataforma se encargue del resto.

**Why this priority**: es el contrato público. Sin esto, los 25+ equipos no tienen forma de adoptar la plataforma; toda la promesa de DevEx (< 1 hora de integración) depende de que este contrato sea trivial.

**Independent Test**: un ingeniero crea `BirthdayNotification` con título y cuerpo, y la clase es invocable desde cualquier parte del monolito sin configuración adicional. Se valida sin necesidad de envío real ni infraestructura externa.

**Acceptance Scenarios**:
1. **Given** un ingeniero crea una clase que hereda del contrato base con `title` y `body`, **When** importa la clase desde otro módulo del monolito, **Then** la clase responde a `send(recipient)` sin requerir registro manual ni configuración extra.
2. **Given** una clase que hereda del contrato base pero **omite** `title` o `body`, **When** alguien intenta usarla, **Then** el sistema falla en tiempo de carga con un mensaje claro indicando qué método falta.
3. **Given** una clase de notificación con `title` y `body` que aceptan contexto, **When** se invoca con un contexto distinto en cada llamada, **Then** los métodos reciben el contexto y pueden personalizar el contenido.

---

### User Story 2 — Capturar el evento de manera idempotente (Priority: P1)

Cuando un ingeniero invoca el envío, la plataforma debe **registrar el evento** en un repositorio durable, asignándole un identificador de trazabilidad (`correlation_id`) y un hash de idempotencia. Si la misma invocación lógica ocurre dos veces dentro de una ventana de tiempo, la segunda **no debe** producir un nuevo registro.

**Why this priority**: la promesa "0% duplicados accidentales" es el diferenciador clave del producto. Sin idempotencia desde la primera capa, todo lo que viene después (decisión, despacho, auditoría) hereda el problema. Resolverlo en el punto de entrada lo soluciona para siempre.

**Independent Test**: invocar dos veces el mismo `send` con los mismos parámetros dentro de la ventana produce **una sola fila** en el repositorio de eventos, y la segunda invocación retorna un resultado tipado como duplicado (no un error).

**Acceptance Scenarios**:
1. **Given** una notificación lista para enviar, **When** se invoca `send(recipient)` por primera vez, **Then** se persiste exactamente una fila con un `correlation_id` único y un `idempotency_hash` derivado de `(recipient, tipo, contexto, ventana)`.
2. **Given** que ya existe un evento registrado con cierto hash, **When** se invoca el mismo envío dentro de la misma ventana de tiempo, **Then** no se crea una nueva fila y el llamador recibe un resultado que indica `:duplicate` (no una excepción).
3. **Given** dos hilos/procesos invocando el mismo envío al mismo tiempo, **When** ambos compiten por persistir, **Then** solo uno gana, el otro recibe `:duplicate`, y la base queda con exactamente una fila.
4. **Given** la misma invocación pero en una **ventana posterior** (por ejemplo al día siguiente), **When** se invoca, **Then** sí se crea una nueva fila (el hash cambia porque la ventana es parte de la entrada).

---

### User Story 3 — Trazabilidad del evento desde el inicio (Priority: P2)

Cuando un evento es capturado, debe tener desde el momento cero un `correlation_id` único y observable. Esta trazabilidad es lo que más adelante permitirá a soporte responder "¿por qué Juan no recibió X?" en segundos.

**Why this priority**: aunque la UI de auditoría llega en una feature posterior, el `correlation_id` debe nacer aquí. Si no se asigna en la ingesta, no hay forma de correlacionar después.

**Independent Test**: cada evento capturado expone un `correlation_id` UUID consultable por el llamador, y dos invocaciones distintas (no duplicadas) tienen `correlation_id` distintos.

**Acceptance Scenarios**:
1. **Given** una invocación nueva, **When** se persiste el evento, **Then** el resultado expone un `correlation_id` UUID que el llamador puede loggear o propagar.
2. **Given** una invocación duplicada, **When** retorna `:duplicate`, **Then** expone el `correlation_id` del evento **original** (no genera uno nuevo), permitiendo agrupar logs.

---

### Edge Cases

- ¿Qué pasa si el `recipient` viene vacío o malformado? → falla temprano antes de persistir, con un mensaje accionable.
- ¿Qué pasa si el `payload`/contexto contiene tipos no serializables? → falla temprano con mensaje accionable; nunca se persiste algo que después no se pueda deserializar.
- ¿Qué pasa si el reloj del servidor cambia (DST, NTP brusco)? → la ventana de idempotencia usa UTC consistente, no la zona local.
- ¿Qué pasa si el almacén está caído? → `send` propaga el error al llamador (el ejercicio asume infra disponible; el comportamiento de retry y degradación queda fuera de esta feature).
- ¿Qué pasa con un `recipient_id` representado de dos maneras equivalentes (ej. `"a@b.com"` vs `"A@B.com"`)? → se normaliza antes de calcular el hash (lowercase + trim) para que invocaciones equivalentes coincidan.
- ¿Qué pasa si una UI permite "rage clicks" sobre un botón que dispara una notificación? → la idempotencia de plataforma colapsará las invocaciones dentro de la ventana, **pero** la mitigación correcta es responsabilidad del frontend (debounce, botón deshabilitado tras click, throttle). La plataforma actúa como red de seguridad, no como sustituto.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sistema DEBE proveer un contrato base que un ingeniero pueda extender declarando `title` y `body` en un solo archivo, sin pasos adicionales de registro.
- **FR-002**: El sistema DEBE permitir invocar `send(recipient, **opciones)` sobre cualquier subclase del contrato base.
- **FR-003**: Cada subclase DEBE poder declarar opcionalmente un template de agrupación (`digest_template`) sin que sea obligatorio para envíos individuales.
- **FR-004**: El sistema DEBE rechazar al cargar (no en runtime) una subclase que omita `title` o `body`, con un mensaje que identifique el método ausente.
- **FR-005**: Cada invocación de `send` DEBE producir como máximo un registro persistido por combinación `(recipient, tipo, contexto, ventana_de_tiempo)`.
- **FR-006**: El sistema DEBE calcular el `idempotency_hash` de forma determinista a partir de los inputs normalizados (`recipient` lowercased y trimmed, tipo, `context_id`, ventana en UTC).
- **FR-007**: La unicidad DEBE ser garantizada a nivel del repositorio (no solo de aplicación), de modo que dos hilos concurrentes no puedan ambos persistir el mismo evento.
- **FR-008**: La invocación duplicada DEBE retornar un resultado tipado `:duplicate` con el `correlation_id` del evento original; **nunca** una excepción de violación de unicidad expuesta al llamador.
- **FR-009**: Cada evento persistido DEBE recibir un `correlation_id` UUID único en el momento de creación, observable desde el resultado de `send`.
- **FR-010**: La ventana de tiempo de idempotencia DEBE ser configurable a nivel de tipo de notificación, con un default sensato (ej. 1 minuto) documentado.
- **FR-011**: El `recipient` DEBE validarse contra un formato mínimo razonable (no vacío, sin saltos de línea, longitud máxima); las validaciones por canal específico (ej. formato email) son responsabilidad de features posteriores.
- **FR-015**: Cada subclase del contrato base PUEDE declarar opcionalmente un identificador de tipo estable. Cuando no se declara, el sistema DEBE derivar uno determinista desde el nombre completo de la clase. El identificador resultante DEBE ser parte del `idempotency_hash` y persistirse en cada `NotificationEvent`.
- **FR-014**: El argumento `recipient` de `send` PUEDE ser un email (endpoint directo) o un identificador interno de usuario. El sistema DEBE detectar el tipo (heurística: contiene `@` → email, en caso contrario → user_id) y normalizarlo a una forma canónica única antes de calcular el `idempotency_hash`, de modo que invocaciones equivalentes a través de cualquiera de las dos formas (cuando ambas refieran al mismo destinatario lógico) **no** se traten como duplicados accidentales en esta feature; la consolidación user_id↔email es responsabilidad del canal de despacho en una feature posterior.
- **FR-012**: Los inputs no serializables al `payload` DEBEN producir error temprano antes de persistir.
- **FR-013**: El sistema DEBE soportar al menos **140 invocaciones por segundo** sostenidas sin degradar la latencia p95 más allá de 50 ms para la operación de ingesta.

### Key Entities

- **Notification (tipo)**: clase declarativa con `title`, `body`, opcional `digest_template`, y metadata como `idempotency_window` y `priority` por defecto. No persiste; existe en código.
- **NotificationEvent**: registro persistido por cada invocación aceptada. Atributos relevantes: tipo, `recipient_id`, `context_id`, `payload`, `idempotency_hash`, `correlation_id`, timestamp.
- **SendResult**: valor de retorno de `send`. Variantes: `:created` (con `correlation_id` nuevo), `:duplicate` (con `correlation_id` del original), `:rejected` (con razón, ej. validación de input).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Un ingeniero crea un nuevo tipo de notificación e invoca `send` desde otra parte del monolito en **menos de 15 minutos**, sin tocar archivos fuera de su módulo.
- **SC-002**: Tras 10.000 invocaciones simultáneas del mismo `(recipient, tipo, contexto)` dentro de la misma ventana, el repositorio contiene **exactamente 1 fila** para esa combinación.
- **SC-003**: Bajo carga sostenida de 140 invocaciones por segundo durante 10 minutos, la latencia p95 de la operación de ingesta se mantiene **por debajo de 50 ms**.
- **SC-004**: 100% de los eventos persistidos exponen un `correlation_id` consultable; ninguna invocación válida termina sin retornar uno.
- **SC-005**: 100% de las invocaciones duplicadas retornan `:duplicate` (no excepción); cero violaciones de constraint propagadas al llamador.

## Assumptions

- La infraestructura de persistencia (PostgreSQL del monolito) está disponible y dimensionada; esta feature no aborda failover ni degradación.
- El reloj de los nodos está sincronizado (NTP); pequeños desvíos no rompen la idempotencia porque la ventana se trunca a unidades discretas.
- El `correlation_id` no necesita ser criptográficamente fuerte; basta con UUIDv4 estándar.
- El default de la ventana de idempotencia se fija en **1 minuto**; cada tipo puede sobreescribirla.
- Las validaciones de formato específicas por canal (ej. validar que un email sea un email) son responsabilidad de la feature de despacho, no de la ingesta.
- No se especifica aquí el formato visual de `title` y `body` (HTML, markdown, plain): se persisten tal cual el equipo los retorne, y la interpretación queda en el canal de despacho.
