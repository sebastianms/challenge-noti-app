# Tasks — 001-foundational-api

**Status**: En progreso · **Date**: 2026-05-10
**Plan**: [plan.md](plan.md) · **Spec**: [spec.md](spec.md) · **ADL**: [ADL-001](../../.design-logs/ADL-001-partition-key-idempotency-window-ts.md)

Convención:
- `[ ]` pendiente · `[/]` en progreso · `[x]` completada · `[-]` diferida (con destino)
- `[P]` paralelizable con otras tareas marcadas igual (archivos distintos, sin dependencia)
- `[US1] [US2] [US3]` story al que pertenece la tarea

---

## Setup — Bootstrap del proyecto Rails

- [x] T001 Inicializar Rails 8.0 con `--database=postgresql --skip-test --skip-action-mailbox --skip-action-text` en raíz del repo (`Gemfile`, `config/`, `bin/`, `db/`)
- [x] T002 [P] Agregar gemas de dev/test al `Gemfile`: `rspec-rails`, `factory_bot_rails`, `simplecov`, `database_cleaner-active_record`, `rubocop`, `rubocop-rails`, `brakeman`, `bundler-audit`. Ejecutar `bundle install`
- [x] T003 [P] Configurar RSpec: `bin/rails generate rspec:install`, mover helpers a `spec/rails_helper.rb`, agregar SimpleCov con umbral 90% en `spec/spec_helper.rb`
- [x] T004 [P] Crear `.rubocop.yml` con configuración base de estilo Rails 8
- [x] T005 [P] Crear `.github/workflows/ci.yml` con jobs: `lint` (rubocop), `security` (brakeman + bundler-audit), `test` (rspec con Postgres en service)
- [x] T006 [P] Crear `docker-compose.yml` con servicio `postgres:16` para desarrollo local
- [x] T007 [P] Configurar `config/database.yml` con env vars (`DATABASE_URL`, fallback a `postgres://postgres:postgres@localhost:5432/`)
- [x] T008 Crear estructura de carpetas: `app/notifications/`, `app/central/ingestion/`, `app/central/models/`, `spec/notifications/`, `spec/central/`. Agregar `.keep` si están vacías
- [x] T009 Configurar autoload: `config/application.rb` con `config.autoload_paths += %W[#{config.root}/app/notifications #{config.root}/app/central]`
- [x] T010 Verificación: `bundle exec rspec` corre vacío en verde, `bundle exec rubocop` pasa, CI verde en PR inicial

**Block Checkpoint Setup**: lint sin warnings · `rspec` verde (suite vacía) · commit `feat(001-foundational/setup): bootstrap Rails 8 + RSpec + CI`

---

## Foundational — Esquema de datos

> Bloquea cualquier user story: sin la tabla particionada y la migración, ni `EventBuilder` ni los tests de idempotencia pueden correr.

- [x] T011 Crear migración `db/migrate/20260510000001_create_notification_events.rb` con DDL completo de `data-model.md`: tabla particionada por `idempotency_window_ts`, UNIQUE `(idempotency_hash, idempotency_window_ts)`, CHECKs, partición default inicial
- [x] T012 Crear modelo `app/central/models/notification_event.rb` con `self.table_name = "notification_events"`, validaciones AR + scope `for_dispatch`
- [x] T013 [P] Crear `spec/factories/notification_events.rb` con FactoryBot factory base + traits (sent, rejected, failed, user_id_recipient)
- [ ] T014 [P] Test de la migración: `spec/db/notification_events_schema_spec.rb` valida estructura de columnas, presencia de constraints, particiones registradas en `pg_partitions`
- [/] T015 Test directo de la UNIQUE constraint: `spec/central/models/notification_event_spec.rb` — archivo creado, pendiente correr (bloqueado: requiere `postgresql-client-16` para `db:schema:dump` con formato SQL)

**Nota**: Se agregó `config.active_record.schema_format = :sql` en `application.rb` porque `schema.rb` no puede representar tablas particionadas (`PARTITION BY RANGE`). Requiere `postgresql-client-16` instalado en la máquina para que `db:schema:dump` funcione (`pg_dump`).

**Block Checkpoint Foundational**: lint · rspec verde · cobertura ≥90% en módulo · ADL-001 ya creado · commit `feat(001-foundational/db): notification_events particionada por window_ts`

---

## User Story 1 — Definir notificación en un solo archivo (P1)

**Goal**: un integrador crea una clase con `title` y `body` y la invoca, sin pasos extra.
**Test independiente**: una `BirthdayNotification` ficticia es invocable desde otro módulo y responde con un `SendResult`.

- [ ] T016 [US1] Crear `app/notifications/abstract_notification.rb` con la API pública: `notification_type`, `idempotency_window`, `resolved_notification_type`, `resolved_idempotency_window`, `title`, `body`, `digest_template`, `send`. Delega a `Central::Ingestion::EventBuilder.build`
- [ ] T017 [P] [US1] Test de carga: `spec/notifications/abstract_notification_spec.rb`
  - una subclase con `title` y `body` no rompe al cargarse
  - una subclase sin `title` lanza `NotImplementedError` con mensaje específico al invocarla
  - una subclase sin `body` lanza `NotImplementedError` con mensaje específico al invocarla
  - `notification_type :stable_id` → `resolved_notification_type` retorna `"stable_id"`
  - sin declarar `notification_type` → retorna FQN normalizado (`"birthday"` para `BirthdayNotification`)
  - `idempotency_window 1.hour` → `resolved_idempotency_window` retorna `1.hour`
  - default → retorna `1.minute`
- [ ] T018 [P] [US1] Crear fixture `spec/support/fixture_notifications.rb` con `BirthdayNotification`, `InvoicePaidNotification`, `BrokenNotification` (sin body) para reutilizar en tests
- [ ] T019 [US1] Verificación quickstart Escenario 1 + Escenario 7

**Block Checkpoint US1**: lint · rspec verde · cobertura ≥90% en `app/notifications/` · Deckard sobre `abstract_notification.rb` · commit `feat(001-foundational/us1): AbstractNotification contract`

---

## User Story 2 — Capturar evento de manera idempotente (P1)

**Goal**: invocaciones equivalentes dentro de la ventana producen una sola fila.
**Test independiente**: 10.000 hilos compitiendo → 1 fila + 9.999 `:duplicate`.

- [ ] T020 [P] [US2] Crear `app/central/ingestion/send_result.rb` con value object frozen y constructores `created`, `duplicate`, `rejected`
- [ ] T021 [P] [US2] Test `spec/central/ingestion/send_result_spec.rb`: estados válidos, frozen, métodos predicado, serialización `to_h`
- [ ] T022 [P] [US2] Crear `app/central/ingestion/recipient_normalizer.rb`: detección email vs user_id por presencia de `@`, lowercase + trim, validaciones (no vacío, sin `\n`, ≤320 chars)
- [ ] T023 [P] [US2] Test `spec/central/ingestion/recipient_normalizer_spec.rb`: tabla de casos email/user_id/inválidos, validar ArgumentError con mensaje correcto
- [ ] T024 [P] [US2] Crear `app/central/ingestion/idempotency_hash.rb`: `compute(notification_type:, recipient_canonical:, context_id:, window_ts:)` retorna SHA256 hex de los inputs concatenados con separador
- [ ] T025 [P] [US2] Test `spec/central/ingestion/idempotency_hash_spec.rb`: determinismo (mismos inputs → mismo hash), sensibilidad (cualquier cambio de input → hash distinto), formato (64 chars hex)
- [ ] T026 [US2] Crear `app/central/ingestion/event_builder.rb` con `EventBuilder.build(...)`: orquesta normalize → hash → INSERT ON CONFLICT, captura `ArgumentError` y devuelve `:rejected`. Implementa `floor_to_window`, `extract_context_id` (default `"no_context"`), `serialize_payload`
- [ ] T027 [US2] Test unitario `spec/central/ingestion/event_builder_spec.rb`:
  - inputs válidos sin context → `:created` con correlation_id UUID
  - segunda invocación equivalente → `:duplicate` con mismo correlation_id
  - context distinto → dos `:created` con correlation_ids distintos
  - recipient inválido → `:rejected` con razón, sin fila en DB
  - payload no serializable (BasicObject) → `:rejected`, sin fila en DB
- [ ] T028 [US2] Test de **borde de ventana** `spec/central/ingestion/window_boundary_spec.rb`: `travel_to 10:23:59` + invocación, `travel_to 10:24:01` + invocación → 2 filas (comportamiento documentado en R-08)
- [ ] T029 [US2] Test de **concurrencia** `spec/integration/idempotency_concurrency_spec.rb`: 50 hilos × 200 invocaciones = 10.000 invocaciones equivalentes → exactamente 1 fila, 9.999 `:duplicate`, 0 excepciones
- [ ] T030 [US2] Verificación quickstart Escenarios 2, 3, 5

**Block Checkpoint US2**: lint · rspec verde (incluye test de concurrencia) · cobertura ≥90% en `app/central/ingestion/` · Deckard sobre `event_builder.rb` · commit `feat(001-foundational/us2): idempotencia con SHA256 + UNIQUE + ON CONFLICT`

---

## User Story 3 — Trazabilidad del correlation_id desde ingesta (P2)

**Goal**: cada evento tiene un `correlation_id` UUID consultable; duplicados retornan el del original.
**Test independiente**: dos invocaciones equivalentes → mismo `correlation_id` retornado, formato UUIDv4 válido.

> Nota: la lógica ya queda implementada en US2; esta story agrega tests específicos y documenta la garantía como contrato observable.

- [ ] T031 [P] [US3] Test `spec/central/ingestion/correlation_id_spec.rb`:
  - `r.correlation_id` matchea regex UUID estándar
  - dos `:created` distintos → correlation_ids distintos
  - `:created` seguido de `:duplicate` → mismos correlation_ids
  - `:rejected` → `correlation_id` es `nil`
- [ ] T032 [P] [US3] Test de logging estructurado `spec/central/ingestion/logging_spec.rb`: cada `EventBuilder.build` emite un log JSON con `correlation_id`, `notification_type`, `state`, observable vía `Rails.logger` capturado en test
- [ ] T033 [US3] Verificación quickstart Escenario 4

**Block Checkpoint US3**: lint · rspec verde · commit `feat(001-foundational/us3): correlation_id observable end-to-end`

---

## Polish — Performance, docs, hardening

- [ ] T034 [P] Crear `lib/tasks/bench.rake` con tarea `bench:ingestion[rps,duration_seconds]` que ejecuta carga sintética con `Parallel`
- [ ] T035 [P] Verificación quickstart Escenario 6: bench a 140 rps × 600 s, validar p95 < 50 ms, 0 errores. Capturar resultado en `docs/bench-results-001.md`
- [ ] T036 [P] Crear `README.md` raíz con: cómo correr el proyecto, cómo agregar una notificación nueva (referenciar Escenario 1 del quickstart), cómo correr el bench
- [ ] T037 [P] Crear `docs/integrators-guide.md` con la guía de integración del párrafo "Regla práctica para integradores" (ventana sugerida según origen del disparo, cuándo pasar `context_id`, casos no cubiertos)
- [ ] T038 Brakeman pass sin findings + `bundle audit` sin vulnerabilidades. Si hay findings false-positive, anotar en `config/brakeman.ignore` con justificación
- [ ] T039 Smoke test final: `bundle exec rspec` corre completo en verde, cobertura ≥90% global reportada por SimpleCov, CI verde en PR

**Block Checkpoint Polish**: lint · rspec verde · cobertura global ≥90% · Brakeman clean · Deckard global · commit `chore(001-foundational/polish): bench, docs, hardening` · push final

---

## Resumen

| Bloque | Tareas | Paralelas | Dependencias |
| :---- | :---- | :---- | :---- |
| Setup | T001–T010 | T002–T007 en paralelo | Ninguna |
| Foundational | T011–T015 | T013–T014 en paralelo | Setup |
| US1 | T016–T019 | T017–T018 en paralelo | Foundational |
| US2 | T020–T030 | T020–T025 en paralelo | Foundational |
| US3 | T031–T033 | T031–T032 en paralelo | US2 |
| Polish | T034–T039 | T034–T037 en paralelo | US1 + US2 + US3 |

**US1 y US2 son independientes técnicamente** (US1 puede mockear el `EventBuilder`), pero en la práctica se desarrollan juntos porque US1 es el contrato público que invoca a US2.

**Total**: 39 tareas. Estimación: 2-3 días de trabajo enfocado, asumiendo familiaridad con Rails 8 y Postgres particionado.
