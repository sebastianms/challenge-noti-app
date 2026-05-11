# Tasks — 004-rules-engine

**Status**: Pendiente · **Date**: 2026-05-11
**Plan**: [plan.md](plan.md) · **Spec**: [spec.md](spec.md) · **Data Model**: [data-model.md](data-model.md) · **Research**: [research.md](research.md)

Convención:
- `[ ]` pendiente · `[/]` en progreso · `[x]` completada · `[-]` diferida (con destino)
- `[P]` paralelizable con otras tareas marcadas igual (archivos distintos, sin dependencia)
- `[US1] [US2] [US3] [US4]` story al que pertenece la tarea

---

## Setup — Estructura

- [ ] T001 [P] Crear carpetas: `app/central/decisioning/`, `spec/central/decisioning/`, `spec/integration/`
- [ ] T002 [P] Agregar a `.env.example` (con valores por defecto comentados): `DIGEST_SCHEDULER_BATCH_SIZE=50`, `DIGEST_SCHEDULER_SLEEP_INTERVAL=60`

**Block Checkpoint Setup**: rubocop verde · rspec sin regresiones · commit `chore(004-rules-engine/setup): carpetas + env vars`

---

## Foundational — Esquema, modelos, value objects, cache

> Bloquea US1, US2, US3, US4. Sin las tablas, modelos y la capa de cache, ningún user story corre.

- [ ] T003 Crear migración `db/migrate/20260512000001_create_notification_rules.rb` con DDL completo de `data-model.md` (tabla + constraints CHECK + UNIQUE + índice parcial `WHERE enabled = TRUE`)
- [ ] T004 [P] Crear migración `db/migrate/20260512000002_create_pending_digests.rb` con DDL completo (tabla + CHECK status + índice parcial sobre `dispatch_at` + índice compuesto `(notification_type, recipient_canonical, status)`)
- [ ] T005 [P] Crear migración `db/migrate/20260512000003_add_notification_type_to_audit.rb`: `ADD COLUMN notification_type TEXT` + índice parcial cubriente `(notification_type, recipient_canonical, created_at) WHERE NOT NULL`
- [ ] T006 [P] Crear modelo `app/central/decisioning/notification_rule.rb` con validaciones (uniqueness, inclusion, numericality) y callbacks `after_save`/`after_destroy` → `RuleCache.invalidate`
- [ ] T007 [P] Crear modelo `app/central/broker/digests/pending_digest.rb` con validaciones (presence, status enum)
- [ ] T008 [P] Crear value object `app/central/decisioning/decision.rb` con factories `dispatch/digest/filter` + predicates `dispatch?/digest?/filter?`
- [ ] T009 [P] Crear `app/central/decisioning/rule_cache.rb` con `fetch`, `invalidate`, `clear_all`. TTL 5 min via `Rails.cache.fetch(..., expires_in: 5.minutes)`. `find_by(notification_type:, enabled: true)`
- [ ] T010 [P] Crear `spec/factories/notification_rules.rb` con factory base + traits (`:with_rate_limit`, `:with_cooldown`, `:with_digest`, `:disabled_channel`)
- [ ] T011 [P] Crear `spec/factories/pending_digests.rb` con factory base + traits (`:ready` con dispatch_at en pasado, `:future` con dispatch_at en futuro, `:consolidated`)
- [ ] T012 [P] Actualizar `spec/factories/notification_audits.rb`: agregar campo `notification_type` (default nil) y trait `:filtered` con metadata reason
- [ ] T013 [P] Test `spec/db/notification_rules_schema_spec.rb`: columnas, UNIQUE constraint, CHECK constraints, índice parcial — 7 ejemplos
- [ ] T014 [P] Test `spec/db/pending_digests_schema_spec.rb`: columnas, CHECK status, índices parciales y compuestos — 6 ejemplos
- [ ] T015 [P] Test `spec/db/notification_audit_schema_spec.rb` (ampliar): valida columna `notification_type` y nuevo índice cubriente — 2 ejemplos
- [ ] T016 [P] Test `spec/central/decisioning/decision_spec.rb`: factories crean el tipo correcto · predicates · accessor de rule_id — 6 ejemplos
- [ ] T017 [P] Test `spec/central/decisioning/rule_cache_spec.rb`: cache miss consulta BD · cache hit no consulta · invalidate borra entrada · clear_all borra todo · enabled=false retorna nil — 6 ejemplos. Usar `Rails.cache = ActiveSupport::Cache::MemoryStore.new` en el before block

**Block Checkpoint Foundational**: migraciones corren sin error · `rspec spec/db/ spec/central/decisioning/decision_spec.rb spec/central/decisioning/rule_cache_spec.rb` verde · commit `feat(004-rules-engine/foundational): schema + modelos + RuleCache + Decision`

---

## User Story 1 — Decisión por reglas (rate limit, cooldown, disabled) (P1)

**Goal**: insertar la capa de decisión antes del Enqueuer. Eventos con regla restrictiva quedan filtrados; sin regla, dispatch normal.
**Test independiente**: crear regla `max_per_day=1`, disparar 2 envíos al mismo destinatario → 1 enqueued + 1 filtered(rate_limited).

- [ ] T018 [US1] Crear `app/central/decisioning/rate_limit_evaluator.rb` con `.exceeded?(rule, event) → bool` consultando `notification_audit` con índice cubriente, ventana 24h, status IN ('dispatched','delivered','enqueued')
- [ ] T019 [P] [US1] Crear `app/central/decisioning/cooldown_evaluator.rb` con `.in_cooldown?(rule, event) → bool` consultando última fila en `notification_audit` con `created_at >= now - rule.cooldown_seconds`
- [ ] T020 [US1] Crear `app/central/decisioning/rules_engine.rb` con `.decide(event:) → Decision`. Orden de evaluación: sin regla → dispatch; channels=[] → filter(disabled); rate_limited → filter; cooldown → filter; digest_window → digest; else → dispatch(rule_id, priority)
- [ ] T021 [US1] Modificar `app/central/ingestion/event_builder.rb`: reemplazar `Enqueuer.enqueue(...)` por `RulesEngine.decide(event:)` + dispatch según `Decision.kind`. Para `:filter` crear audit `filtered` con metadata `{reason, rule_id}`. Para `:dispatch` poblar audit con `notification_type` y respetar `decision.priority` si presente
- [ ] T022 [US1] Modificar `app/central/broker/enqueuer.rb` y `app/central/broker/worker.rb` para que las audit entries que crean también incluyan `notification_type` (lookup del evento)
- [ ] T023 [P] [US1] Test `spec/central/decisioning/rate_limit_evaluator_spec.rb`: max_per_day=3 + 2 audits → false · max_per_day=3 + 3 audits → true · audit fuera de ventana no cuenta · solo audits con status terminal cuentan · max_per_day=nil → false — 6 ejemplos
- [ ] T024 [P] [US1] Test `spec/central/decisioning/cooldown_evaluator_spec.rb`: cooldown=60 + envío hace 30s → true · cooldown=60 + envío hace 120s → false · sin audits previos → false · cooldown_seconds=nil → false — 5 ejemplos
- [ ] T025 [P] [US1] Test `spec/central/decisioning/rules_engine_spec.rb`: sin regla → dispatch · channels=[] → filter(disabled) · rate_limited → filter(rate_limited) · cooldown → filter(cooldown) · digest_window → digest · regla normal → dispatch con priority — 8 ejemplos
- [ ] T026 [US1] Test `spec/integration/rules_pipeline_spec.rb` (escenarios 1, 2, 3 del quickstart): rate limit fuerza filtered · channels=[] → no enqueue · sin regla → comportamiento idéntico Phase 3 — 4 ejemplos
- [ ] T027 [US1] Verificar que `spec/integration/email_dispatch_spec.rb` (existente) sigue verde sin cambios — compatibilidad hacia atrás

**Block Checkpoint US1**: lint · rspec verde · cobertura ≥90% en `app/central/decisioning/` · Deckard · commit `feat(004-rules-engine/us1): RulesEngine + rate limit + cooldown + disabled`

---

## User Story 2 — Digest (agrupar envíos) (P1)

**Goal**: eventos con regla `digest_window_seconds` se acumulan en `pending_digests`; un worker los consolida en 1 envío por grupo `(type, recipient)`.
**Test independiente**: regla con window=60s; 5 envíos al mismo destinatario → 5 pending_digests; tras `travel 65.seconds` + `DigestScheduler.process_batch` → 1 fila en dispatch_queue.

- [ ] T028 [US2] Modificar `EventBuilder` (o crear `app/central/decisioning/digest_enqueuer.rb`): cuando `Decision.digest?`, insertar fila en `pending_digests` con `dispatch_at = now + rule.digest_window_seconds`, `rule_snapshot` JSONB, status `pending`. Crear audit `pending_digest` con metadata `{rule_id, dispatch_at}`
- [ ] T029 [US2] Crear `app/central/broker/digest_scheduler.rb` con `.process_batch(batch_size: 50)`: SKIP LOCKED claim, agrupación por `(notification_type, recipient_canonical)`, INSERT en `dispatch_queue` con payload fusionado, UPDATE pending a `consolidated` con `consolidated_into=correlation_id`. Crear audit `digested` por cada item original con `metadata.digest_correlation_id`
- [ ] T030 [P] [US2] Crear `lib/tasks/digest_scheduler.rake` con `digest_scheduler:run[batch_size,sleep_interval]` para foreground
- [ ] T031 [P] [US2] Test `spec/central/broker/digest_scheduler_spec.rb`: claim solo dispatched items vencidos · agrupa correctamente por (type, recipient) · pending vencido se consolida en 1 fila dispatch_queue · items futuros no se tocan · concurrencia con 2 threads no duplica consolidación (metadata `:threads`) · status='consolidated' tras procesar · audit `digested` creado por cada item — 8 ejemplos
- [ ] T032 [P] [US2] Test del nuevo flujo en `spec/central/decisioning/rules_engine_spec.rb` (extender): cuando hay regla con digest_window, EventBuilder no crea fila en dispatch_queue sino en pending_digests
- [ ] T033 [US2] Test `spec/integration/rules_pipeline_spec.rb` (extender con escenarios 4, 8 del quickstart): digest end-to-end · concurrencia del scheduler — 3 ejemplos

**Block Checkpoint US2**: lint · rspec verde · cobertura ≥90% en `app/central/broker/digest_scheduler.rb` y digest path · Deckard · commit `feat(004-rules-engine/us2): PendingDigest + DigestScheduler + agrupación`

---

## User Story 3 — Edición en caliente (P1)

**Goal**: cambios a `notification_rules` se reflejan en ≤ 5 min sin reiniciar workers. Cache hit rate alto.
**Test independiente**: crear regla, hacer 2 envíos OK, actualizar regla a más restrictiva, hacer 1 envío más → último queda filtered tras invalidación de cache.

- [ ] T034 [US3] Test `spec/central/decisioning/rule_cache_spec.rb` (extender): después de `rule.update!`, `RuleCache.fetch` retorna la versión actualizada inmediatamente (callback after_save) — 2 ejemplos adicionales
- [ ] T035 [P] [US3] Test `spec/integration/rules_pipeline_spec.rb` (extender con escenario 5): edición en caliente refleja en próximo envío — 2 ejemplos
- [ ] T036 [P] [US3] Test `spec/integration/rules_pipeline_spec.rb` (extender con escenario 7): cache hit rate — 100 envíos del mismo tipo → ≤ 1 query a `notification_rules`. Usar `ActiveSupport::Notifications.subscribe("sql.active_record")` — 1 ejemplo

**Block Checkpoint US3**: lint · rspec verde · Deckard · commit `feat(004-rules-engine/us3): cache invalidation hot-reload + verificación cache hit rate`

---

## User Story 4 — Pipeline auditado con rule_id (P2)

**Goal**: cada decisión persiste `rule_id` y `reason` en `notification_audit.metadata` para que `/admin/audits` muestre el motivo del filtrado.
**Test independiente**: filtrar un envío por rate_limit, consultar `/admin/audits?correlation_id=...` y ver el row con `metadata.rule_id` y `metadata.reason`.

> Nota: la lógica de poblado de metadata se implementa en T021 (US1) y T028/T029 (US2). Este bloque solo agrega verificación y muestra cómo /admin/audits los presenta.

- [ ] T037 [US4] Test `spec/controllers/admin/audits_controller_spec.rb` (extender): la vista muestra `metadata.reason` y `metadata.rule_id` para filas filtered y digested — 2 ejemplos
- [ ] T038 [P] [US4] Test `spec/integration/rules_pipeline_spec.rb` (extender con escenario 6): audit incluye rule_id correcto y reason — 2 ejemplos
- [ ] T039 [US4] Actualizar vista `app/views/admin/audits/_row.html.erb`: agregar columna `reason` extraída de `metadata.reason` (mostrar `—` si nil)

**Block Checkpoint US4**: lint · rspec verde · Deckard · commit `feat(004-rules-engine/us4): audit con rule_id + reason visible en /admin/audits`

---

## Polish — Docs, ADLs, hardening

- [ ] T040 [P] Crear `.design-logs/ADL-008-rails-cache-rule-strategy.md`: decisión cache Rails.cache vs alternativas (memoría proceso, Redis directo), TTL 5 min, invalidación explícita, single-node vs multi-node tradeoffs
- [ ] T041 [P] Crear `.design-logs/ADL-009-rule-snapshot-pending-digests.md`: por qué snapshot JSONB en lugar de FK (sobrevivir borrado de regla, FR-010)
- [ ] T042 [P] Ampliar `.design-logs/ADL-005-skip-locked-job-claiming.md`: nota "Extensión 2026-05-12 — `pending_digests` con `DigestScheduler` reusa el patrón"
- [ ] T043 [P] Actualizar `README.md`: sección "Motor de reglas" con CRUD desde consola Rails (`NotificationRule.create!`), explicación de campos, ejemplo de digest. Agregar `digest_scheduler:run` a tabla de rake tasks
- [ ] T044 [P] Actualizar `specs/roadmap.md`: marcar Phase 5 como `[DONE]` con descripción real de implementación
- [ ] T045 Smoke test final: suite completa verde · cobertura ≥90% global · rubocop 0 offenses · Brakeman 0 findings · bundler-audit clean

**Block Checkpoint Polish**: lint · rspec verde · cobertura global ≥90% · Brakeman clean · Deckard global · commit `chore(004-rules-engine/polish): ADL-008/009, ADL-005 ext, README, roadmap, smoke` · push final

---

## Resumen

| Bloque | Tareas | Paralelas | Dependencias |
| :---- | :---- | :---- | :---- |
| Setup | T001–T002 | T001–T002 en paralelo | Ninguna |
| Foundational | T003–T017 | T004–T017 en paralelo (T003 primero) | Setup |
| US1 | T018–T027 | T019, T023–T025 en paralelo | Foundational |
| US2 | T028–T033 | T030–T032 en paralelo | Foundational (US1 no es bloqueante técnicamente) |
| US3 | T034–T036 | T035–T036 en paralelo | US1 (extiende RulesEngine) |
| US4 | T037–T039 | T038 en paralelo | US1 + US2 |
| Polish | T040–T045 | T040–T044 en paralelo | US1 + US2 + US3 + US4 |

**Total**: 45 tareas. Estimación: 2-3 días de trabajo enfocado.

**US1 y US2 son independientes** técnicamente — pueden desarrollarse en paralelo con dos developers. US3 extiende US1 (test de invalidación de cache que US1 ya implementó vía callbacks). US4 verifica que US1/US2 dejaron metadata correcta y agrega columna en la vista.
