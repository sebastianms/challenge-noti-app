# Feature Specification: Observabilidad, performance & hardening

**Feature Branch**: `009-observability-perf-hardening`
**Created**: 2026-05-12
**Status**: Draft

## Overview

Cierre de Phase 10 del roadmap. Esta feature deja la plataforma lista para entregar al equipo de SRE/plataforma: métricas operativas observables, evidencia empírica de que sostiene el target de carga del MVP (140 rps × 1h), pipeline de seguridad formalizado en CI, y documentación operativa para que un developer cree una notificación nueva y un on-call resuelva incidentes sin escalación.

No agrega capacidades de negocio nuevas — convierte capacidades existentes en operables.

---

## User Scenarios & Testing

### User Story 1 — SRE observa salud del sistema en vivo (Priority: P1)

Un ingeniero de SRE necesita saber, sin abrir psql ni leer logs crudos, el estado actual de la cola de envío, el tamaño de la DLQ y la tasa de errores de los últimos minutos. Hoy esa información solo existe consultando tablas directamente o esperando el dashboard admin (que muestra agregados de 7 días, no in-vivo).

**Why this priority**: sin métricas en vivo, no hay alarmas; sin alarmas, los incidentes se descubren por reclamos de usuarios. Es el bloqueo más caro.

**Independent Test**: con el sistema corriendo en local, hacer `curl /metrics` y verificar que devuelve un payload Prometheus-style con al menos `queue_depth`, `dlq_size`, `dispatch_errors_total{class=...}`, `events_ingested_total`, `bounce_rate_5m`. Disparar 1 evento, refrescar `/metrics`, ver que `events_ingested_total` incrementó.

**Acceptance Scenarios**:
1. **Given** el worker corriendo con 10 jobs pendientes, **When** se consulta `/metrics`, **Then** la respuesta incluye `queue_depth 10` y el endpoint responde en < 100 ms.
2. **Given** un job que falló MAX_ATTEMPTS veces, **When** se consulta `/metrics`, **Then** `dlq_size` refleja el aumento y `dispatch_errors_total{class="TransientError"}` incrementó.
3. **Given** webhooks de Sendgrid recibidos en los últimos 5 min con bounces, **When** se consulta `/metrics`, **Then** `bounce_rate_5m` refleja la proporción correctamente.
4. **Given** un usuario no autenticado, **When** intenta acceder a `/metrics`, **Then** recibe 401 (el endpoint expone datos operativos, no es público).

---

### User Story 2 — Equipo de plataforma valida que sostiene 140 rps (Priority: P1)

La fundación del MVP es sostener 140 rps de ingesta sostenidos por 1 hora sin degradar p95 de latencia. Hoy ese número está afirmado pero no medido. El equipo de plataforma necesita un script repetible que cualquier ingeniero pueda correr antes de cada release y un reporte con la evidencia.

**Why this priority**: el SLO de `mission.md` está sin verificar. Sin esto, el roadmap no puede declararse cumplido.

**Independent Test**: ejecutar `bin/load_test --rps 140 --duration 1h` (o equivalente con tooling externo tipo `k6`/`vegeta`) contra el endpoint de ingesta. Al terminar, generar `specs/009-observability-perf-hardening/reports/load-test-<fecha>.md` con: p50/p95/p99 de latencia de ingesta, p95 de delay enqueue→dispatch, error rate, queue_depth máximo observado, conclusión vs. SLO.

**Acceptance Scenarios**:
1. **Given** el sistema corriendo con 1 worker, **When** se ejecuta el load test de 140 rps × 1 h, **Then** p95 de ingesta < 200 ms durante toda la prueba y el reporte se genera automáticamente.
2. **Given** el load test corriendo, **When** la cola supera 1000 jobs pendientes, **Then** la prueba registra el evento pero no falla — la métrica `queue_depth_max` lo refleja en el reporte final.
3. **Given** el reporte generado, **When** se revisa, **Then** indica explícitamente PASS/FAIL contra el SLO y los percentiles concretos.

---

### User Story 3 — CI bloquea releases con vulnerabilidades o secrets (Priority: P2)

Brakeman y bundle-audit ya corren en CI desde Phase 9 (descubrió CVE-2026-32700 en Devise). Falta formalizar: el pipeline debe **fallar** ante hallazgos nuevos (no solo reportarlos), debe tener un mecanismo documentado para excluir falsos positivos con justificación, y debe estar visible en el README como gate obligatorio.

**Why this priority**: la integración existe pero no es bloqueante. Un developer puede mergear ignorando el output. Formalizar es bajo esfuerzo y cierra una superficie de riesgo concreta.

**Independent Test**: introducir intencionalmente una vulnerabilidad de Brakeman (ej. interpolación SQL) en una rama de prueba, abrir PR → CI rojo, PR no mergeable. Removerla → CI verde.

**Acceptance Scenarios**:
1. **Given** un PR con un finding de Brakeman criticidad ≥ Medium, **When** CI corre, **Then** el job falla con exit code distinto de 0 y bloquea el merge.
2. **Given** un PR con una dependencia con CVE pendiente, **When** CI corre, **Then** `bundle-audit` reporta y falla el job.
3. **Given** un falso positivo aceptado, **When** está documentado en `.brakeman.ignore` con justificación, **Then** CI pasa y el archivo de ignore está versionado.

---

### User Story 4 — Developer nuevo monta el proyecto vía Docker y crea una notificación en < 1 hora (Priority: P2)

El SLO funcional principal del producto: un developer que nunca tocó el repo debe poder clonar, levantar el stack completo con Docker Compose (sin instalar Ruby, Postgres ni gemas en la máquina anfitriona), ejecutar los tests dentro del contenedor, y agregar una notificación nueva en menos de una hora siguiendo documentación. Hoy esa documentación está dispersa entre specs, ADLs y código; los pasos de setup (build de imagen, migraciones, seeds, worker, suite de tests) no están consolidados ni garantizados para correr 100% containerizados.

**Why this priority**: la métrica de éxito de `mission.md` depende de esto. Sin docs consolidadas la promesa del MVP no se sostiene en handoff. Setup containerizado elimina la variable "qué versión de Ruby/Postgres tenés instalada" y hace el onboarding determinista.

**Independent Test**: dar el README a un developer que no participó del proyecto y una máquina limpia con **solo Docker + Git instalados** (sin Ruby, sin Postgres, sin Bundler). Cronometrar desde "git clone" hasta "envié una notificación nueva al endpoint y vi el audit en `/admin/audits`". Target < 60 min total. Si el developer tiene que `apt install` o `brew install` algo más allá de Docker, el test FALLA.

**Acceptance Scenarios**:
1. **Given** una máquina limpia con solo Docker + Git, **When** un developer sigue la sección "Setup con Docker" del README, **Then** en < 15 minutos tiene `docker compose up` levantando app + db + worker, con migraciones aplicadas y seeds (admin_user, reglas demo) cargados.
2. **Given** los contenedores corriendo, **When** ejecuta `docker compose exec app bin/rspec` (o equivalente documentado), **Then** la suite completa pasa en verde sin necesidad de instalar gemas en host.
3. **Given** el stack containerizado, **When** sigue la sección "Probar la aplicación", **Then** ejecuta el flujo end-to-end (login admin en `http://localhost:PORT/admin`, disparar notificación via `docker compose exec app bin/rails console` o curl al endpoint, ver audit, ver dashboard) sin pedir ayuda.
4. **Given** el README actualizado, **When** un developer sigue la sección "Crear una notificación nueva", **Then** llega a `FooNotification.send("a@b.com")` funcionando dentro del contenedor — incluye dónde crear el archivo (volume-montado), cómo registrar la regla opcional, y cómo verificar en `/admin/audits`.
5. **Given** un on-call sin contexto del proyecto, **When** consulta el runbook ante una alarma "DLQ size > 100", **Then** sigue 5 pasos concretos (consulta UI → reintento masivo → revisa motivo dominante → escala o descarta) sin necesidad de leer código.
6. **Given** un on-call frente a "bounce rate > 5%", **When** consulta el runbook, **Then** encuentra: cómo identificar el dominio afectado, cómo pausar envíos a ese dominio (blacklist scope=domain), cómo comunicar a stakeholders.

---

### User Story 5 — Home page guía al visitante por la aplicación (Priority: P2)

Hoy `/` redirige directo a `/admin/login` (o 404, según el deploy). Un visitante que abre el sitio sin contexto no entiende qué hace la plataforma, qué endpoints públicos existen (webhooks, métricas, ingesta), ni cómo acceder al panel. Falta un landing mínimo que oriente.

**Why this priority**: complementa la docs de US4. La docs sirve a quien clona el repo; el home sirve a quien abre el browser. Mismo problema (descubribilidad), distinto canal.

**Independent Test**: abrir `http://localhost:PORT/` sin sesión iniciada. La página debe explicar en menos de 30 segundos: (1) qué hace el sistema, (2) cómo es el flujo (ingesta → reglas → dispatch → audit), (3) links a `/admin/login`, `/metrics` (con nota de auth), `/webhooks/sendgrid` (con nota de POST), y al repositorio. No debe requerir login.

**Acceptance Scenarios**:
1. **Given** un visitante sin sesión, **When** abre `/`, **Then** ve un landing con título del producto, descripción breve, diagrama o lista del flujo, y links a panel admin + repo + docs.
2. **Given** un visitante autenticado como admin, **When** abre `/`, **Then** el landing muestra un CTA prominente "Ir al dashboard" además del contenido informativo.
3. **Given** el landing, **When** se inspecciona, **Then** está alineado visualmente con el resto del panel admin (mismo layout, tipografía, paleta) — no es un placeholder genérico.

---

### User Story 6 — Diseño visual consistente y profesional en el panel admin (Priority: P3)

El panel admin (`/admin/*`) se construyó incrementalmente fase por fase priorizando funcionalidad. Las vistas funcionan pero el diseño es inconsistente: tablas sin estilo unificado, formularios con espaciados ad-hoc, colores de estado (success/error/warning) usados de forma irregular, navegación sin jerarquía visual clara. Para una entrega final de challenge, el "look & feel" pesa.

**Why this priority**: P3 porque no es bloqueante para SLOs ni operación. Pero sí afecta percepción del stakeholder en la demo final. Hacerlo después del resto evita re-trabajo si los specs de las fases anteriores cambian.

**Independent Test**: recorrer las 6 vistas principales (`/`, `/admin/dashboard`, `/admin/rules`, `/admin/audits`, `/admin/blacklist`, `/admin/templates`, `/admin/dlq`) y verificar contra una checklist: header consistente, breadcrumbs/nav activo, tabla con mismo estilo, botones primary/secondary/danger con misma semántica, mensajes flash con mismo posicionamiento, formularios con labels alineados.

**Acceptance Scenarios**:
1. **Given** el panel admin, **When** se navega entre secciones, **Then** el layout (header + nav lateral o superior) se mantiene idéntico y la sección activa se resalta.
2. **Given** cualquier vista con tabla, **When** se inspecciona, **Then** usa el mismo componente/estilo (mismas clases CSS, mismo padding, mismo zebra striping o no, decisión consistente).
3. **Given** cualquier acción destructiva (delete, discard, force retry), **When** se renderiza, **Then** usa un botón con clase `btn-danger` consistente con confirmación.
4. **Given** un mensaje flash (success/error/warning), **When** aparece, **Then** está posicionado en el mismo lugar (top of content area) y con el mismo estilo de cada tipo.
5. **Given** un formulario, **When** tiene errores de validación, **Then** los muestra con el mismo patrón (mensaje arriba del field + borde rojo en el field).

---

### User Story 7 — Tour de la aplicación para revisores y stakeholders (Priority: P2)

Un revisor del challenge o un stakeholder que abre el panel por primera vez no sabe qué hace cada sección, qué datos ve, ni en qué orden explorar. El runbook cubre incidentes; el README cubre setup técnico; ninguno de los dos guía la exploración del producto. Falta un documento narrativo que explique cada sección en términos de negocio, qué se puede hacer ahí, y qué datos de ejemplo buscar.

**Why this priority**: directamente relevante para la evaluación del challenge. Un revisor que puede auto-orientarse en < 5 min impresiona más que uno que tiene que adivinar qué hace cada botón.

**Independent Test**: dar `docs/app-tour.md` a alguien que nunca vio la app. Verificar que sin ayuda adicional puede: (a) entender qué es cada sección, (b) ejecutar al menos 1 acción en cada una (ver audits de una notificación, editar una regla, ver la DLQ, previsualizar un template).

**Acceptance Scenarios**:
1. **Given** `docs/app-tour.md`, **When** un revisor lo lee, **Then** entiende el propósito de las 7 secciones del panel en < 5 minutos: Dashboard, Reglas, Auditoría, Blacklist, Templates, DLQ, y el home público.
2. **Given** el tour, **When** cubre cada sección, **Then** incluye: para qué sirve, qué rol tiene acceso, qué acción típica hacer (con el comando o pasos exactos para llegar a ese estado con datos de demo), y qué observar en pantalla.
3. **Given** el tour, **When** se lee junto con el README, **Then** no hay contradicción — el tour referencia el setup del README, no lo repite.
4. **Given** el home en `/`, **When** incluye un link a `docs/app-tour.md` en el repo, **Then** el revisor puede llegar al tour desde la landing sin buscar en el filesystem.

---

### Edge Cases

- ¿Qué pasa si `/metrics` se consulta con la base de datos caída? → Debe responder 503 con un body mínimo, no 500 con stack trace.
- ¿Qué pasa si el load test se interrumpe a mitad? → Debe generar un reporte parcial con la duración real y marcar "INTERRUMPIDO".
- ¿Brakeman reporta finding en código de tests? → Excluir `spec/` por configuración explícita.
- ¿Falso positivo de bundle-audit? → Mecanismo documentado: `bundler-audit` permite `--ignore CVE-XXXX-XXXX` con comentario en archivo de config.

---

## Requirements

### Functional Requirements

- **FR-001**: El sistema MUST exponer un endpoint `/metrics` que devuelva métricas en formato Prometheus text exposition al menos para: `queue_depth`, `dlq_size`, `events_ingested_total`, `dispatch_errors_total{class}`, `bounce_rate_5m`, `webhook_lag_seconds`.
- **FR-002**: El endpoint `/metrics` MUST estar protegido (HTTP Basic con credencial dedicada `METRICS_BASIC_AUTH_*`) — no debe ser anónimo aunque sea local.
- **FR-003**: El sistema MUST proveer un script ejecutable (`bin/load_test` o equivalente con tool externo documentado) que dispare carga sostenida a un rps configurable y por una duración configurable.
- **FR-004**: El script de carga MUST generar un reporte markdown en `specs/009-.../reports/` con percentiles, error rate, conclusión PASS/FAIL vs. SLO.
- **FR-005**: CI MUST fallar el workflow si Brakeman reporta findings de severidad ≥ Medium sin estar en `.brakeman.ignore`.
- **FR-006**: CI MUST fallar el workflow si `bundle-audit` reporta CVEs sin estar en su lista de ignore documentada.
- **FR-007**: El README MUST contener una sección "Setup con Docker" con pasos numerados desde `git clone` hasta stack levantado con DB migrada + seeds + suite verde, usando **solo** Docker + Docker Compose (sin Ruby/Postgres/Bundler en host). Pre-requisitos: Docker version mínima y puertos requeridos. Comandos copy-paste-ables.
- **FR-008**: El proyecto MUST proveer un `docker-compose.yml` (o equivalente) que orqueste al menos: servicio `app` (Rails + worker), servicio `db` (Postgres), con volumen para código (hot reload en dev) y healthcheck en db. Setup, tests, migraciones y consola MUST ser ejecutables vía `docker compose exec` sin requerir gemas en host.
- **FR-009**: El README MUST contener una sección "Probar la aplicación" con el flujo end-to-end mínimo ejecutado vía Docker (login admin, disparar notificación con `docker compose exec app bin/rails ...` o curl, verificar audit, ver dashboard). Cada paso con comando + resultado esperado.
- **FR-010**: El README MUST contener una sección "Crear una notificación nueva" con pasos concretos ejecutados dentro de los contenedores (crear archivo en código montado, opcional crear regla, opcional crear template, probar via `docker compose exec`) — máximo 1 página.
- **FR-011**: El proyecto MUST incluir un runbook operacional (`docs/runbook.md`) cubriendo al menos: DLQ saturada, bounce rate alto, Sendgrid down, partición de auditoría faltante.
- **FR-012**: Las métricas expuestas en `/metrics` MUST tener overhead < 50 ms por scrape (validable con `docker compose exec app curl /metrics` y `time`).
- **FR-018**: El proyecto MUST incluir `docs/app-tour.md` con una sección por cada área del panel admin (Dashboard, Reglas, Auditoría, Blacklist, Templates, DLQ) más el home público. Cada sección MUST incluir: propósito en 2-3 líneas, roles con acceso, acción típica con pasos exactos (usando datos del seed), y qué observar como resultado.
- **FR-019**: El home `/` MUST enlazar al `docs/app-tour.md` en el repositorio (link absoluto al repo GitHub) de forma visible en el footer o en la sección de endpoints.
- **FR-013**: Las alarmas recomendadas (queue_depth > N, dlq_size > N, bounce_rate > X%, error_rate > Y%) MUST estar documentadas con umbrales sugeridos y rationale en el runbook, aunque la configuración de alarmas en sí dependa del proveedor cloud y queda fuera del scope de código.
- **FR-014**: La aplicación MUST exponer una ruta pública `GET /` (sin autenticación) que renderice un landing con descripción del producto, flujo conceptual, y links a panel admin + repositorio. Si hay sesión admin activa, debe mostrar un CTA "Ir al dashboard".
- **FR-015**: El panel admin MUST tener un sistema de diseño consistente: un único layout base reutilizado por todas las secciones, componentes compartidos para tablas, formularios, botones (`primary`/`secondary`/`danger`), mensajes flash, y badges de estado. No deben coexistir múltiples estilos para el mismo componente.
- **FR-016**: La navegación admin MUST resaltar visualmente la sección activa y mostrar solo links a secciones permitidas por el rol del usuario logueado (consistente con `RoleAuthorizer::PERMISSIONS`).
- **FR-017**: Los formularios admin MUST mostrar errores de validación con un patrón consistente (mensaje + estado visual en el field) en las 4 vistas con forms (rules, blacklist, templates, dlq discard).

### Key Entities

- **Métrica**: nombre + tipo (counter/gauge/histogram) + labels + descripción. No se persiste — se computa on-demand desde tablas existentes (`dispatch_queue`, `notification_audit`).
- **Reporte de load test**: archivo markdown timestamped con summary numérico y veredicto.
- **Runbook entry**: escenario + síntomas + pasos diagnósticos + pasos de remediación + criterios de escalación.

---

## Success Criteria

### Measurable Outcomes

- **SC-001**: El endpoint `/metrics` responde en < 100 ms p95 con la suite poblada de datos realistas.
- **SC-002**: Una ejecución de load test 140 rps × 1 h completa con p95 de ingesta < 200 ms y error rate < 0.5%. Evidencia archivada en `reports/`.
- **SC-003**: Un PR con vulnerabilidad introducida intencionalmente queda bloqueado por CI (no mergeable) y el reporte indica qué línea/CVE.
- **SC-004**: Un developer externo al equipo, partiendo de máquina limpia con **solo Docker + Git**, completa setup containerizado (clone → `docker compose up` → tests verdes dentro del contenedor) en < 15 minutos siguiendo el README. No debe instalar Ruby, Postgres, Bundler ni gemas en host.
- **SC-005**: El mismo developer crea y dispara una notificación nueva en < 60 minutos totales (incluyendo setup) sin asistencia, todo ejecutado vía `docker compose`.
- **SC-006**: Un on-call sin contexto previo resuelve un escenario simulado de DLQ saturada en < 15 minutos siguiendo el runbook.
- **SC-007**: Un visitante sin contexto abre `/` y, en < 30 segundos, identifica qué hace el sistema y cómo acceder al panel (validable con walkthrough cronometrado).
- **SC-008**: Una auditoría visual de las 6+ vistas admin reporta cero inconsistencias en: layout base, componentes de tabla, semántica de botones, posicionamiento de flash, patrón de errores de form.
- **SC-009**: Un revisor sin contexto previo lee `docs/app-tour.md` y ejecuta al menos 1 acción en cada sección del panel en < 15 minutos usando solo el tour y los datos del seed.

---

## Clarifications

### Session 2026-05-12

- **Visual stack**: Tailwind CSS via CDN (`<script src="https://cdn.tailwindcss.com">`) en el layout admin. Sin build step, sin gemas, sin Propshaft pipeline para CSS. Aplica al landing público (`/`) y al panel admin completo. Decisión justificada en research.md.
- **Load test tooling**: k6 ejecutado como servicio adicional en `docker-compose.yml` (perfil `load-test`). Script JS en `specs/009-.../load/scenario.js`; output JSON parseado por un script Ruby (`bin/load_report`) que genera el reporte markdown en `specs/009-.../reports/load-test-<fecha>.md`. Cero dependencias en host.
- **Source de métricas**: queries on-demand a la DB en cada scrape (`SELECT COUNT(*)` sobre `dispatch_queue`, `notification_audit`). Sin estado en proceso, sin counters in-memory. Cache HTTP corto (5 s) en respuesta para evitar storms si Prometheus scrapea agresivamente.
- **Worker en Compose**: servicio dedicado `worker` siempre encendido junto a `app` y `db`. `docker compose up` levanta el stack completo y la cola se procesa sin pasos manuales. Refleja deploy productivo.

## Assumptions

- Métricas se exponen en formato Prometheus text aunque no haya servidor Prometheus configurado — facilita scrape manual y futura integración cloud sin cambiar el código.
- El umbral de Brakeman es ≥ Medium (Weak/Low se reportan pero no bloquean) — Weak en proyectos Rails típicamente son falsos positivos en helpers.
- El runbook se escribe en español neutro (consistente con el resto del proyecto).
- "Developer externo" para SC-004 se simula con un teammate o se valida con un walkthrough cronometrado autoevaluado durante la entrega, idealmente en una VM/container limpio sin Ruby instalado para garantizar la independencia del host.
- El stack ya usa Docker Compose para tests (servicio `test`); esta feature consolida y documenta su uso como **camino primario de desarrollo**, no como ambiente alternativo. Se agregan servicios `app` (web), `worker` (cola), y opcionalmente `k6` (perfil load-test).
- Tailwind via CDN evita Propshaft/jsbundling. Aceptable trade-off: dependencia de internet en dev (insignificante para challenge demo), zero-config, fácil de migrar a Tailwind precompilado si crece el proyecto.

---

## Out of Scope

- Integración real con CloudWatch / Datadog / NewRelic — fuera del entorno demo.
- Configuración de alarmas en proveedor cloud (solo se documentan umbrales recomendados).
- Tracing distribuido (OpenTelemetry) — sobreingeniería para un servicio mono-proceso.
- Profiling de queries — la suite de tests ya cubre N+1 vía `bullet` o equivalente si se detectase.
