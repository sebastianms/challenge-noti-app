# Tasks — 002-email-dispatch

**Status**: En progreso · **Date**: 2026-05-10
**Plan**: [plan.md](plan.md) · **Spec**: [spec.md](spec.md) · **Data Model**: [data-model.md](data-model.md)

Convención:
- `[ ]` pendiente · `[/]` en progreso · `[x]` completada · `[-]` diferida (con destino)
- `[P]` paralelizable con otras tareas marcadas igual (archivos distintos, sin dependencia)
- `[US1] [US2] [US3]` story al que pertenece la tarea

---

## Setup — Dependencias y configuración

- [x] T001 Agregar `gem "webmock", "~> 3.0"` al grupo `:test` en `Gemfile` y ejecutar `bundle install`
- [x] T002 [P] Crear `spec/support/webmock.rb` con `require "webmock/rspec"` y `WebMock.disable_net_connect!(allow_localhost: true)`
- [x] T003 [P] Crear estructura de carpetas: `app/central/broker/`, `app/central/channels/`, `app/central/audit/` con `.keep` si están vacías
- [x] T004 [P] Actualizar `config/application.rb`: agregar `app/central/broker`, `app/central/channels`, `app/central/audit` a `config.autoload_paths`

**Block Checkpoint Setup**: `bundle exec rspec` corre en verde con WebMock activo (sin nuevos specs aún) · `bundle exec rubocop` sin offenses

---

## Foundational — Esquema de datos

> Bloquea US1, US2, US3: sin las tablas y los modelos AR nada puede correr.

- [x] T005 Crear migración `db/migrate/20260510000002_create_dispatch_queue.rb` con DDL completo de `data-model.md`: tabla `dispatch_queue`, CHECK constraints, índice parcial `WHERE status = 'pending'`
- [x] T006 Crear migración `db/migrate/20260510000003_create_notification_audit.rb` con DDL de `notification_audit` particionada por mes + partición inicial `notification_audit_2026_05` + índices GIN y por `correlation_id`
- [x] T007 [P] Crear modelo `app/central/broker/dispatch_queue.rb` con `BACKOFF_SCHEDULE`, `MAX_ATTEMPTS`, validaciones AR, `next_backoff`, `permanent_failure?`
- [x] T008 [P] Crear modelo `app/central/audit/notification_audit.rb` con validaciones AR básicas
- [x] T009 [P] Crear `spec/factories/dispatch_queues.rb` con factory base + traits (`in_flight`, `failed`, `done`)
- [x] T010 [P] Crear `spec/factories/notification_audits.rb` con factory base + traits por status
- [x] T011 [P] Test de migración `spec/db/dispatch_queue_schema_spec.rb`: columnas, constraints CHECK, índice parcial presente en `pg_indexes` — 8 ejemplos
- [x] T012 [P] Test de migración `spec/db/notification_audit_schema_spec.rb`: particionamiento en `pg_partitions`, índices GIN, partición inicial — 6 ejemplos

**Block Checkpoint Foundational**: migraciones corren sin error · `rspec spec/db/` verde · modelos AR válidos

---

## User Story 1 — Despacho de email funcional end-to-end (P1)

**Goal**: `WelcomeNotification.send("a@b.com")` → job en `dispatch_queue` → Worker → Sendgrid 202 → `done`.

- [ ] T013 [US1] Crear `app/central/channels/channel_strategy.rb`: clase abstracta con `deliver` y `channel_name` que levantan `NotImplementedError`
- [ ] T014 [P] [US1] Crear `app/central/channels/channel_registry.rb`: `register(name, channel)`, `for(name)` (levanta `KeyError` si no existe), `registered_names`
- [ ] T015 [P] [US1] Test `spec/central/channels/channel_registry_spec.rb`: register, for, KeyError en canal desconocido, registered_names — 5 ejemplos
- [ ] T016 [US1] Crear `app/central/channels/sendgrid_adapter.rb`: `deliver(event, recipient_email, correlation_id:)`, construye payload v3, envía con `Net::HTTP`, propaga `X-Correlation-ID`, clasifica respuesta HTTP en `:delivered` / error permanente / error transitorio
- [ ] T017 [P] [US1] Test `spec/central/channels/sendgrid_adapter_spec.rb` con WebMock:
  - stub 202 → `:delivered`
  - stub 503 → levanta `TransientError`
  - stub 400 → levanta `PermanentError`
  - header `X-Correlation-ID` presente en la request
  - payload incluye `subject`, `content`, `to`, `from`
  — 8 ejemplos
- [ ] T018 [US1] Crear `app/central/channels/email_channel.rb`: implementa `ChannelStrategy`, valida que `recipient_id` contenga `@` (levanta `ArgumentError` si no), delega a `SendgridAdapter`, registra en `ChannelRegistry` como `:email`
- [ ] T019 [P] [US1] Test `spec/central/channels/email_channel_spec.rb`:
  - deliver con email válido → `:delivered` (WebMock stub 202)
  - deliver con user_id sin @ → `ArgumentError`
  - `channel_name` → `"email"`
  — 5 ejemplos
- [ ] T020 [US1] Crear `app/central/broker/enqueuer.rb`: `Enqueuer.enqueue(event, priority: :standard)` → INSERT en `dispatch_queue` + INSERT en `notification_audit` con status `enqueued`
- [ ] T021 [P] [US1] Test `spec/central/broker/enqueuer_spec.rb`:
  - crea job `pending` en `dispatch_queue`
  - registra audit `enqueued`
  - prioridad configurable
  — 5 ejemplos
- [ ] T022 [US1] Modificar `app/central/ingestion/event_builder.rb`: en `persist`, tras INSERT exitoso (no duplicado), llamar a `Central::Broker::Enqueuer.enqueue(event)` dentro de la misma transacción
- [ ] T023 [P] [US1] Test `spec/central/ingestion/event_builder_spec.rb` (ampliar): duplicate no crea job · created sí crea job — 2 ejemplos adicionales (manteniendo los 7 existentes)
- [ ] T024 [US1] Crear `app/central/broker/worker.rb`: `process_batch(batch_size: 10)` — SELECT SKIP LOCKED, marca `in_flight`, llama al canal, registra audit `dispatched` + `delivered`/`failed`, backoff o DLQ. Método `start(batch_size:, sleep_interval:)` para loop continuo
- [ ] T025 [P] [US1] Test `spec/central/broker/worker_spec.rb`:
  - procesa job pending → done (WebMock stub 202)
  - SKIP LOCKED: dos workers simultáneos no toman el mismo job
  - job done no se vuelve a procesar
  — 5 ejemplos

**Block Checkpoint US1**: lint · rspec verde · cobertura ≥90% en `app/central/broker/` y `app/central/channels/` · Deckard · commit `feat(002-email/us1): broker + email channel + sendgrid adapter`

---

## User Story 2 — Reintentos con backoff y DLQ (P1)

**Goal**: fallo → backoff 1m/5m/25m → DLQ con `failed_reason`. Sin reintentos para errores permanentes.

- [ ] T026 [US2] Ampliar `app/central/broker/worker.rb`: manejar `TransientError` (backoff + re-pending) vs `PermanentError` (DLQ inmediato). Definir módulo `Central::Broker::Errors` con `TransientError` y `PermanentError`
- [ ] T027 [P] [US2] Test `spec/central/broker/worker_spec.rb` (ampliar):
  - 1 fallo transitorio → attempts=1, status=pending, next_attempt_at ≈ now+1min
  - 3 fallos consecutivos → status=failed, attempts=3, `failed_reason` documentado
  - 4to intento no ocurre (job permanece failed)
  - error permanente (400) → DLQ en el primer intento
  — 6 ejemplos adicionales
- [ ] T028 [P] [US2] Test `spec/central/broker/dispatch_queue_spec.rb`:
  - `next_backoff` retorna los valores correctos por nivel de attempts
  - `permanent_failure?` es true cuando `attempts >= MAX_ATTEMPTS`
  — 4 ejemplos

**Block Checkpoint US2**: lint · rspec verde · commit `feat(002-email/us2): backoff + DLQ`

---

## User Story 3 — Correlation ID propagado al proveedor (P2)

**Goal**: `X-Correlation-ID` del evento llega como header HTTP a Sendgrid.

- [ ] T029 [US3] Verificar que `spec/central/channels/sendgrid_adapter_spec.rb` (T017) ya cubre este contrato — añadir ejemplo explícito de reintento si falta: el reintento usa el mismo `correlation_id` original
- [ ] T030 [P] [US3] Test de integración `spec/integration/email_dispatch_spec.rb`:
  - Escenario 1 (happy path): send → process_batch → status done, audits [enqueued, dispatched, delivered]
  - Escenario 5 (duplicate no genera job): send x2 → dispatch_queue.count == 1
  - Escenario 6 (X-Correlation-ID): header verificado con WebMock `have_been_requested`
  — 6 ejemplos

**Block Checkpoint US3**: lint · rspec verde · cobertura global ≥90% · Deckard · commit `feat(002-email/us3): correlation_id propagado`

---

## Polish — Hardening, docs, smoke test

- [ ] T031 [P] Crear `lib/tasks/worker.rake` con `worker:run[batch_size,sleep_interval]` para ejecutar el Worker en foreground desde CLI
- [ ] T032 [P] Crear `spec/support/sendgrid_stubs.rb` con helpers `stub_sendgrid_success` y `stub_sendgrid_error(status:)` reutilizables
- [ ] T033 [P] Crear ADL-003 en `.design-logs/ADL-003-broker-dispatch-queue-skip-locked.md`
- [ ] T034 [P] Crear ADL-004 en `.design-logs/ADL-004-webmock-http-stubbing.md`
- [ ] T035 Smoke test final: todos los ejemplos de `quickstart.md` cubiertos por specs · `bundle exec rubocop` 0 offenses · cobertura ≥90% en módulos nuevos · Brakeman 0 findings
- [ ] T036 Actualizar README con sección "Canales" y mención del Worker rake task

**Block Checkpoint Polish**: lint · rspec verde · cobertura global ≥90% · Brakeman clean · commit `chore(002-email/polish): rake worker, ADLs, docs` · push

---

## Resumen

| Bloque | Tareas | Paralelas | Dependencias |
| :---- | :---- | :---- | :---- |
| Setup | T001–T004 | T002–T004 en paralelo | Ninguna |
| Foundational | T005–T012 | T007–T012 en paralelo | Setup |
| US1 | T013–T025 | T014–T015, T017, T019, T021, T023, T025 en paralelo | Foundational |
| US2 | T026–T028 | T027–T028 en paralelo | US1 |
| US3 | T029–T030 | T029–T030 en paralelo | US2 |
| Polish | T031–T036 | T031–T034 en paralelo | US1 + US2 + US3 |

**Total**: 36 tareas. Estimación: 2 días de trabajo enfocado.
