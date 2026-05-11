# Tasks — 003-audit-query

**Status**: Pendiente · **Date**: 2026-05-11
**Plan**: [plan.md](plan.md) · **Spec**: [spec.md](spec.md) · **Data Model**: [data-model.md](data-model.md) · **Research**: [research.md](research.md)

Convención:
- `[ ]` pendiente · `[/]` en progreso · `[x]` completada · `[-]` diferida (con destino)
- `[P]` paralelizable con otras tareas marcadas igual (archivos distintos, sin dependencia)
- `[US1] [US2] [US3] [US4]` story al que pertenece la tarea

---

## Setup — Dependencias y rutas

- [x] T001 Agregar `gem "ed25519", "~> 1.3"` al `Gemfile` (grupo principal) y ejecutar `bundle install`
- [x] T002 [P] Agregar al `config/routes.rb`: `namespace :webhooks do post "sendgrid", to: "sendgrid_events#create" end` y `namespace :admin do resources :audits, only: [:index] end`
- [x] T003 [P] Documentar nuevas env vars en `.env.example`: `SENDGRID_WEBHOOK_PUBLIC_KEY`, `AUDIT_BASIC_AUTH_USER`, `AUDIT_BASIC_AUTH_PASSWORD`, `AUDIT_RETENTION_MONTHS`
- [x] T004 [P] Crear estructura de carpetas: `app/central/webhooks/`, `app/controllers/webhooks/`, `app/controllers/admin/`, `app/views/admin/audits/`, `spec/central/webhooks/`, `spec/controllers/webhooks/`, `spec/controllers/admin/`

**Block Checkpoint Setup**: `rubocop` sin warnings · `rspec` verde · commit `feat(003-audit/setup): gem ed25519 + rutas + env vars`

---

## Foundational — Esquema de datos

> Bloquea US1, US2, US3, US4: sin las columnas nuevas y la tabla `webhook_events` ningún user story corre.

- [x] T005 Crear migración `db/migrate/20260511000001_extend_notification_audit_with_source_and_recipient.rb` con `ADD COLUMN recipient_canonical TEXT`, `ADD COLUMN source TEXT NOT NULL DEFAULT 'internal' CHECK (source IN ('internal','sendgrid_webhook'))`, índice parcial sobre `recipient_canonical` (WHERE NOT NULL), índice compuesto `(status, created_at)`
- [x] T006 Crear migración `db/migrate/20260511000002_create_webhook_events.rb` con DDL completo de `data-model.md`: tabla `webhook_events` + índice parcial sobre `status IN ('pending','processing')`
- [x] T007 [P] Extender `app/central/audit/notification_audit.rb`: agregar `validates :source, inclusion: { in: %w[internal sendgrid_webhook] }`
- [x] T008 [P] Crear modelo `app/central/webhooks/webhook_event.rb` con validaciones AR (`payload`, `signature`, `signature_ts`, status enum)
- [x] T009 [P] Crear `spec/factories/webhook_events.rb` con factory base + traits (`processing`, `processed`, `failed`)
- [x] T010 [P] Actualizar `spec/factories/notification_audits.rb` para incluir traits `source: :sendgrid_webhook` y `recipient_canonical`
- [x] T011 [P] Test `spec/db/notification_audit_schema_spec.rb` (ampliar): valida columnas `source` y `recipient_canonical` con sus constraints, índices presentes en `pg_indexes`
- [x] T012 [P] Test `spec/db/webhook_events_schema_spec.rb`: columnas, CHECK status, índice parcial presente — 6 ejemplos

**Block Checkpoint Foundational**: migraciones corren sin error · `rspec spec/db/` verde · modelos AR válidos · commit `feat(003-audit/foundational): schema (audit columns + webhook_events)`

---

## User Story 1 — Búsqueda por correlation_id (P1)

**Goal**: dado un `correlation_id`, retornar el timeline completo ordenado.
**Test independiente**: insertar 3 entradas de audit para un correlation_id + 5 para otros; query retorna exactamente las 3 ordenadas por `created_at ASC`.

- [x] T013 [US1] Modificar `app/central/broker/enqueuer.rb`: setear `source: "internal"` y `recipient_canonical: event.recipient_canonical` en el INSERT de audit
- [x] T014 [P] [US1] Modificar `app/central/broker/worker.rb`: setear `source: "internal"` y `recipient_canonical` (resuelto via `event.recipient_canonical`) en los audits `dispatched`/`delivered`/`failed`
- [x] T015 [US1] Actualizar `spec/central/broker/enqueuer_spec.rb` y `spec/central/broker/worker_spec.rb`: verificar que las nuevas filas de audit tienen `source = "internal"` y `recipient_canonical` poblado
- [x] T016 [US1] Crear `app/central/audit/audit_search.rb` con interfaz `AuditSearch.new(correlation_id:).call → Array<NotificationAudit>` ordenado por `created_at ASC`
- [x] T017 [P] [US1] Test `spec/central/audit/audit_search_spec.rb` (modo correlation_id): retorna 3 entradas ordenadas · lista vacía cuando no existe · ignora otros filtros si correlation_id presente — 4 ejemplos
- [x] T018 [US1] Verificación quickstart Escenario 1

**Block Checkpoint US1**: lint · rspec verde · cobertura ≥90% en `app/central/audit/` · Deckard · commit `feat(003-audit/us1): AuditSearch por correlation_id + audit source/recipient`

---

## User Story 2 — Filtros + paginación + endpoint Hotwire (P1)

**Goal**: buscar por destinatario, status, fechas (combinables) con paginación.
**Test independiente**: 60 audits creados, filtro `status=failed` retorna 50 en página 1 + total=60.

- [x] T019 [US2] Extender `app/central/audit/audit_search.rb`: soportar `recipient`, `status`, `from`, `to`, `source`, `page`, `per_page` (cap 50). Devolver objeto `Result` con `items`, `total`, `page`, `per_page`, `has_next?`
- [x] T020 [P] [US2] Test `spec/central/audit/audit_search_spec.rb` (modo filtros): cada filtro individual, combinación AND, paginación con LIMIT/OFFSET, cap de per_page, orden DESC — 8 ejemplos
- [x] T021 [US2] Crear `app/controllers/admin/audits_controller.rb` con `http_basic_authenticate_with` desde env vars + acción `index` que delega a `AuditSearch` y renderiza `index.html.erb`
- [x] T022 [P] [US2] Crear vista `app/views/admin/audits/index.html.erb` con form de filtros + tabla de resultados + paginación (links a `?page=N`)
- [x] T023 [P] [US2] Crear parcial `app/views/admin/audits/_row.html.erb` con columnas `created_at`, `correlation_id`, `recipient_canonical`, `status`, `source`, `channel`
- [x] T024 [P] [US2] Test `spec/controllers/admin/audits_controller_spec.rb`: 401 sin auth · 200 con auth válido · render incluye filtros aplicados · paginación correcta — 6 ejemplos
- [x] T025 [US2] Test de integración `spec/integration/audit_search_spec.rb`: setup de 60 envíos sintéticos · filtros combinados verifican cardinalidad y orden — 4 ejemplos
- [x] T026 [US2] Verificación quickstart Escenarios 2, 7, 8

**Block Checkpoint US2**: lint · rspec verde · cobertura ≥90% en `app/controllers/admin/` y AuditSearch · Deckard · commit `feat(003-audit/us2): filtros + paginación + endpoint Hotwire`

---

## User Story 3 — Webhook handler async (P1)

**Goal**: SendGrid POST con firma válida → 200 rápido + persistencia en webhook_events → Worker procesa → audit entries.
**Test independiente**: POST con firma válida persiste 1 fila en webhook_events; Worker la procesa y crea N audits con `source = sendgrid_webhook`.

- [x] T027 [US3] Crear `app/central/webhooks/sendgrid_signature.rb` con `SendgridSignature.verify(payload:, signature:, timestamp:, public_key:)` usando `Ed25519::VerifyKey`. Retorna `true` / `false`
- [x] T028 [P] [US3] Test `spec/central/webhooks/sendgrid_signature_spec.rb`: firma válida → true · firma inválida → false · timestamp manipulado → false · public key ausente → raise — 5 ejemplos. Generar pares de llaves Ed25519 fijos en spec/support
- [x] T029 [P] [US3] Crear helper `spec/support/sendgrid_webhook_signer.rb` con `post_signed_webhook(payload, key:)` y helpers para test fixtures de payloads de SendGrid (delivered, bounce, spam)
- [x] T030 [US3] Crear `app/controllers/webhooks/sendgrid_events_controller.rb` con acción `create`: lee raw body, verifica firma, valida JSON parseable, persiste `WebhookEvent` con status `pending`, responde JSON `{received: N, webhook_event_id: ID}` — 200/400/401 según contrato
- [x] T031 [P] [US3] Test `spec/controllers/webhooks/sendgrid_events_controller_spec.rb`: 200 con firma válida + batch persistido · 401 firma inválida · 400 payload no parseable · 401 sin headers de firma · response time razonable (no procesa eventos inline) — 6 ejemplos
- [x] T032 [US3] Crear `app/central/webhooks/sendgrid_event_processor.rb` con `process(webhook_event)`: itera `webhook_event.payload`, traduce `event` → `status` (delivered/bounced/spam_reported/dropped/deferred/raw), crea entradas en `NotificationAudit` con `source = sendgrid_webhook` y metadata del bounce type
- [x] T033 [P] [US3] Test `spec/central/webhooks/sendgrid_event_processor_spec.rb`: traducción correcta de cada tipo de evento · `recipient_canonical` poblado desde `event.email` · metadata incluye `type` y `sg_timestamp` · evento sin `correlation_id` se persiste con NULL — 6 ejemplos
- [x] T034 [US3] Crear `app/central/broker/webhook_event_worker.rb` con `WebhookEventWorker.process_batch(batch_size: 10)`: SKIP LOCKED sobre `webhook_events WHERE status = 'pending'`, marca `processing`, llama a `SendgridEventProcessor`, marca `processed`. Si excepción → `failed` con `failed_reason`
- [x] T035 [P] [US3] Test `spec/central/broker/webhook_event_worker_spec.rb`: procesa job pending → processed · SKIP LOCKED dos workers no toman el mismo job · excepción del processor → status=failed con reason · job processed no se vuelve a tomar — 6 ejemplos
- [x] T036 [US3] Test de integración `spec/integration/webhook_ingest_spec.rb`: POST signed → 200 · webhook_event pending · WebhookEventWorker.process_batch · audit entries con source=sendgrid_webhook y status correctos — 5 ejemplos cubre Escenarios 3, 4, 5
- [x] T037 [US3] Agregar tarea rake `lib/tasks/webhook_worker.rake` con `webhook_worker:run[batch_size,sleep_interval]` para foreground

**Block Checkpoint US3**: lint · rspec verde · cobertura ≥90% en `app/central/webhooks/` y controller · Deckard · ADL-007 (Ed25519) creado · commit `feat(003-audit/us3): webhook async + Ed25519 + WebhookEventWorker`

---

## User Story 4 — PartitionManager (P2)

**Goal**: rotar particiones mensuales sin downtime.
**Test independiente**: estado inicial con particiones [2025-11, 2026-03, 2026-05] + retención 6 meses → tras rotate: existe 2026-06, eliminada 2025-11, conservada 2026-03 (safety < 3 meses).

- [x] T038 [US4] Crear `app/central/audit/partition_manager.rb` con `PartitionManager.new(table:, retention_months:)`: métodos `create_next_month_partition`, `drop_old_partitions` (con safety guardrail 3 meses), `rotate` (combina ambos)
- [x] T039 [P] [US4] Test `spec/central/audit/partition_manager_spec.rb`: crea partición siguiente · idempotencia (segunda invocación no falla) · dropea particiones más viejas que retention · respeta safety guardrail 3 meses · log warning si retention < 3 — 7 ejemplos
- [x] T040 [US4] Crear `lib/tasks/partitions.rake` con `partitions:rotate` que invoca PartitionManager para `notification_audit` con retención desde env var `AUDIT_RETENTION_MONTHS` (default 6)
- [x] T041 [US4] Verificación quickstart Escenario 6

**Block Checkpoint US4**: lint · rspec verde · cobertura ≥90% en PartitionManager · Deckard · commit `feat(003-audit/us4): PartitionManager + rake partitions:rotate`

---

## Polish — Docs, ADLs, hardening

- [ ] T042 [P] Crear `.design-logs/ADL-007-ed25519-sendgrid-webhook-signature.md`: contexto (SendGrid Signed Webhooks v3), decisión (Ed25519 con gema dedicada), alternativas, consecuencias
- [ ] T043 [P] Ampliar `.design-logs/ADL-005-skip-locked-job-claiming.md` con nota: "Extensión 2026-05-11 — el mismo patrón se reusa para `webhook_events` con `WebhookEventWorker`"
- [ ] T044 [P] Actualizar `README.md`: sección "Auditoría consultable" (endpoint `/admin/audits`, env vars de HTTP Basic) + "Webhook de SendGrid" (endpoint, configuración de public key) + tabla de rake tasks (worker:run, webhook_worker:run, partitions:rotate)
- [ ] T045 [P] Actualizar `specs/roadmap.md`: marcar Phase 4 como `[DONE]` con descripción real de implementación
- [ ] T046 Smoke test final: suite completa verde · cobertura ≥90% global · rubocop 0 offenses · Brakeman 0 findings · bundler-audit sin vulnerabilidades

**Block Checkpoint Polish**: lint · rspec verde · cobertura global ≥90% · Brakeman clean · Deckard global · commit `chore(003-audit/polish): ADL-007, README, roadmap, smoke` · push final

---

## Resumen

| Bloque | Tareas | Paralelas | Dependencias |
| :---- | :---- | :---- | :---- |
| Setup | T001–T004 | T002–T004 en paralelo | Ninguna |
| Foundational | T005–T012 | T007–T012 en paralelo | Setup |
| US1 | T013–T018 | T014, T017 en paralelo | Foundational |
| US2 | T019–T026 | T020, T022–T024 en paralelo | US1 (reusa AuditSearch) |
| US3 | T027–T037 | T028–T029, T031, T033, T035 en paralelo | Foundational (independiente de US1/US2 técnicamente) |
| US4 | T038–T041 | T039 en paralelo | Foundational |
| Polish | T042–T046 | T042–T045 en paralelo | US1 + US2 + US3 + US4 |

**Total**: 46 tareas. Estimación: 2-3 días de trabajo enfocado.

**US1, US3 y US4 son técnicamente independientes** una vez Foundational está listo (cada una toca módulos distintos). US2 depende de US1 porque extiende `AuditSearch`. Se pueden ejecutar US3 y US4 en paralelo con US1 si hay más de un desarrollador.
