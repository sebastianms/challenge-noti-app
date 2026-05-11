# Tasks — 005-blacklist-bounces

**Feature**: Blacklist + bounces automáticos
**Status**: pendiente · **Total**: 40 tareas

Convenciones:
- `[P]` = paralelizable (archivos distintos, sin dependencia inmediata)
- `[USn]` = pertenece a User Story n; sub-tasks de Setup/Foundational/Polish no llevan label de story
- Cada TaskID es único e incremental

---

## Setup

- [x] T001 Crear migration `db/migrate/20260512170000_create_notification_blacklist.rb` con tabla, CHECKs (`blacklist_scope_target_chk`, `blacklist_scope_values_chk`, `blacklist_source_values_chk`), UNIQUE `(recipient_canonical, scope, target) NULLS NOT DISTINCT`, índices `idx_blacklist_lookup` y `idx_blacklist_source_created`
- [x] T002 Correr `bin/rails db:migrate` y verificar `db/schema.rb` (o `structure.sql`) actualizado con la nueva tabla
- [x] T003 [P] Crear modelo `app/central/decisioning/notification_blacklist.rb` con validaciones AR: `validates :scope, inclusion: { in: %w[global type channel] }`, `validates :source, inclusion: { in: %w[manual admin_ui hard_bounce dropped spamreport] }`, validación custom de scope/target coherentes
- [x] T004 [P] Crear factory `spec/support/factories/notification_blacklists.rb` con trait `:global`, `:type_scoped`, `:channel_scoped`, `:hard_bounce`
- [x] T005 Spec de schema `spec/central/decisioning/notification_blacklist_schema_spec.rb`: verifica CHECK rechaza `scope=global + target='x'`, CHECK rechaza `scope=type + target=NULL`, UNIQUE rechaza duplicados, `NULLS NOT DISTINCT` rechaza dos `(recipient, global, NULL)` (7 ejemplos)

**Block Checkpoint Setup**: rubocop sin warnings · rspec verde · commit `feat(005-blacklist-bounces/setup): tabla + modelo + factory + schema spec`

---

## Foundational

> Bloqueante para US1 y US2. Implementa el evaluator y lo cablea en el `EventBuilder`.

- [x] T006 Crear `app/central/decisioning/blacklist_evaluator.rb` con `BlacklistEvaluator.match(event:, channel: "email")` ejecutando query única OR (ver R2 de research.md) y `LIMIT 1`. Predicado conveniencia `blacklisted?(...)`
- [x] T007 [P] Spec `spec/central/decisioning/blacklist_evaluator_spec.rb`: sin fila → nil · scope global matchea cualquier tipo/canal · scope=type matchea solo ese tipo · scope=channel matchea solo ese canal · múltiples filas → LIMIT 1 · casing del recipient → matchea por canonical (6 ejemplos)
- [x] T008 Extender `app/central/ingestion/event_builder.rb`: invocar `BlacklistEvaluator.match` después del check de duplicado y antes de `RulesEngine.decide`. Si matchea → audit `filtered` con `metadata: { reason: "blacklisted", blacklist_id, scope, target }` y retornar `SendResult.filtered`
- [x] T009 [P] Spec `spec/central/ingestion/event_builder_blacklist_spec.rb`: con blacklist matching → no se llama a `RulesEngine.decide` (mock) · audit registrado con reason=blacklisted · `dispatch_queue` vacío · sin blacklist → flujo normal continúa (4 ejemplos)
- [x] T010 Actualizar `config/application.rb` si hace falta autoload del nuevo archivo (`decisioning/` ya está en autoload_paths desde feature 004 — solo verificar)

**Block Checkpoint Foundational**: rubocop sin warnings · rspec verde · Deckard review · commit `feat(005-blacklist-bounces/foundational): BlacklistEvaluator + integración en EventBuilder`

---

## User Story 1 — Opt-out manual desde consola (P1)

> Compliance crea una fila con `source=manual` desde consola Rails. Cualquier `.send` posterior al destinatario queda filtrado.

- [x] T011 [US1] Integration spec `spec/integration/blacklist_pipeline_spec.rb` escenario US1a: `NotificationBlacklist.create!(scope: "global", source: "manual", ...)`. `BirthdayNotification.send` con casing distinto → `:filtered`, audit con reason=blacklisted, `DispatchQueue.count == 0`
- [x] T012 [P] [US1] Integration spec mismo archivo escenario US1b: `scope=type, target=birthday` → `BirthdayNotification.send` filtered, `MfaNotification.send` created
- [x] T013 [P] [US1] Integration spec escenario US1c: `scope=channel, target=email` → envío por email filtered (verificar via `apply_decision` o end-to-end)
- [x] T014 [P] [US1] Spec edge case: blacklist con `recipient_canonical` ya canonicalizado matchea contra `event.send(recipient: "User@X.com")` (uppercase) — verifica que canonicalization se aplica en ambos lados
- [x] T015 [US1] Verificar que `RecipientNormalizer.canonicalize` se llame antes de cualquier insert/lookup en blacklist (auditar código añadido en T006/T008)

**Block Checkpoint US1**: rubocop sin warnings · rspec verde · cobertura ≥95% en `blacklist_evaluator.rb` · commit `feat(005-blacklist-bounces/us1): opt-out manual filtra envíos pre-reglas`

---

## User Story 2 — Auto-blacklist desde webhook (P1)

> SendGrid envía `bounce` (hard) / `dropped` / `spamreport` → `WebhookEventWorker` inserta fila con `scope=channel, target=email`, idempotente por UNIQUE.

- [x] T016 [US2] Extender `app/central/broker/webhook_event_worker.rb`: agregar método privado `hard_failure?(event)` (true para `bounce` con `type=bounce`, `dropped`, `spamreport`; false para `bounce` con `type=blocked`, `deferred`, `delivered`)
- [x] T017 [US2] En `webhook_event_worker.rb` extender `process_event`: cuando `hard_failure?(event)` → INSERT en `notification_blacklist` con `scope='channel'`, `target='email'`, `source` mapeado del event type, `reason = "#{event['reason']} (sg_event_id=#{event['sg_event_id']})"`, dentro de la misma transacción que el audit. Usar `insert_all(... on_conflict_do_nothing)`
- [x] T018 [P] [US2] Spec `spec/central/broker/webhook_event_worker_blacklist_spec.rb`: evento `bounce + type=bounce` → blacklist creada con source=hard_bounce (1 ejemplo)
- [x] T019 [P] [US2] Spec mismo archivo: evento `bounce + type=blocked` → NO blacklist (solo audit) (1 ejemplo)
- [x] T020 [P] [US2] Spec mismo archivo: evento `dropped` → blacklist source=dropped · evento `spamreport` → blacklist source=spamreport · evento `deferred` → no blacklist (3 ejemplos)
- [x] T021 [P] [US2] Spec mismo archivo: evento duplicado (mismo recipient ya bloqueado) → 1 sola fila (idempotencia ON CONFLICT) (1 ejemplo)
- [x] T022 [P] [US2] Spec mismo archivo: forzar fallo en blacklist insert (stub que raise) → audit roll-backea (1 ejemplo, valida transaccionalidad)
- [x] T023 [US2] Integration spec `spec/integration/blacklist_pipeline_spec.rb` escenario US2: POST `/webhooks/sendgrid` firmado con payload `bounce` hard → `WebhookEventWorker.new.process_batch` → `NotificationBlacklist.where(recipient_canonical: ...).exists?` true · siguiente `WelcomeNotification.send` al mismo destinatario → filtered

**Block Checkpoint US2**: rubocop sin warnings · rspec verde · cobertura ≥95% en webhook_event_worker (ramal hard_failure) · commit `feat(005-blacklist-bounces/us2): auto-blacklist desde hard bounce/dropped/spamreport`

---

## User Story 3 — UI admin para listar y remover (P2)

> Soporte abre `/admin/blacklist`, filtra, remueve con motivo. Audit `blacklist_removed` queda registrado.

- [x] T024 [US3] Crear controller `app/controllers/admin/blacklist_controller.rb` con `index`, `create`, `destroy`. HTTP Basic con mismas envvars que `/admin/audits` (refactor a concern si conviene)
- [x] T025 [US3] Agregar rutas en `config/routes.rb`: `resources :blacklist, only: [:index, :create, :destroy], controller: "admin/blacklist"` bajo namespace `:admin`
- [x] T026 [US3] Vista `app/views/admin/blacklist/index.html.erb` con form de filtros (`recipient`, `scope`, `target`, `source`) + tabla + paginación (cap 50). Reutilizar estilos de `/admin/audits`
- [x] T027 [P] [US3] Partial `app/views/admin/blacklist/_row.html.erb`: una fila con columnas `recipient_canonical`, `scope`, `target`, `source`, `reason` truncado, `created_at`, botón "Remover" (form POST con `_method=delete`)
- [x] T028 [P] [US3] Partial `app/views/admin/blacklist/_form.html.erb`: form de alta manual con `recipient`, `scope`, `target`, `reason`
- [x] T029 [US3] En `destroy`: dentro de una transacción, crear audit `blacklist_removed` con `notification_type="_blacklist_removed_"`, `correlation_id=SecureRandom.uuid`, `metadata={blacklist_id, scope, target, removed_by: request.authorization→user, reason: params[:reason]}` → DELETE de la fila
- [x] T030 [US3] En `create`: aplicar `RecipientNormalizer.canonicalize` antes de insertar. Si retorna nil → flash error 422
- [x] T031 [P] [US3] Spec request `spec/requests/admin/blacklist_spec.rb`: GET sin auth → 401 · GET con auth → 200 + tabla · GET con filtro `?scope=channel` → solo filas matching (3 ejemplos)
- [x] T032 [P] [US3] Spec request mismo archivo: POST con datos válidos → 302 + fila creada con `source=admin_ui` · POST inválido (CHECK constraint) → 422 (2 ejemplos)
- [x] T033 [P] [US3] Spec request mismo archivo: DELETE → 302 + fila borrada + audit `blacklist_removed` con `removed_by` y `reason` en metadata · DELETE 404 si id no existe (2 ejemplos)
- [x] T034 [US3] Integration spec `spec/integration/blacklist_pipeline_spec.rb` escenario US3: flujo completo create via UI → list → destroy via UI → audit visible en `/admin/audits` con notification_type=`_blacklist_removed_`

**Block Checkpoint US3**: rubocop sin warnings · rspec verde · cobertura ≥95% en `blacklist_controller.rb` · commit `feat(005-blacklist-bounces/us3): UI /admin/blacklist con remoción auditada`

---

## Polish

- [ ] T035 [P] Crear `.design-logs/ADL-010-blacklist-pre-rules-evaluation.md`: contexto (compliance no negociable), decisión (evaluación antes de RulesEngine), alternativas (rama dentro de reglas, hook post-encolado), consecuencias positivas/negativas, referencias a R1/R3/R5
- [ ] T036 [P] Actualizar `README.md`: sección "Blacklist y opt-outs" con ejemplo consola (`NotificationBlacklist.create!`), tabla de fields, link a `/admin/blacklist`, breve nota sobre auto-blacklist desde webhook
- [ ] T037 [P] Actualizar `specs/roadmap.md`: marcar Phase 6 como `[DONE]` con bullets de implementación y link a ADL-010
- [ ] T038 Smoke test: `bundle exec rubocop` (0 offenses) + `bundle exec rspec` (suite completa verde, cobertura ≥95% en módulos nuevos) + `bundle exec brakeman --no-pager` (0 warnings) + `bundle exec bundler-audit` (clean)
- [ ] T039 Benchmark p95 del `BlacklistEvaluator` (script de quickstart.md): seedear 100k filas, medir 1000 lookups, verificar p95 ≤ 5 ms (SC-005). Si falla → ajustar índice o query
- [ ] T040 Marcar todas las tareas como `[x]` en este archivo, commit `chore(005-blacklist-bounces/polish): ADL-010, README, roadmap, smoke + benchmark` y push

**Block Checkpoint Polish**: smoke completo verde · benchmark p95 ≤ 5 ms · commit + push final

---

## Dependencias

```
Setup (T001-T005)
    ↓
Foundational (T006-T010)
    ↓
    ├─→ US1 (T011-T015)   [P1] ─┐
    ├─→ US2 (T016-T023)   [P1] ─┼─→ Polish (T035-T040)
    └─→ US3 (T024-T034)   [P2] ─┘
```

US1, US2 y US3 son independientes entre sí tras Foundational. Pueden implementarse en paralelo si hay capacidad; el plan secuencial respeta prioridad (P1 antes que P2).

## Notas

- Tests son **opcionales** según SDD pero la spec exige cobertura ≥ 95% en módulos nuevos (SC-006) — por eso están incluidos en cada bloque.
- Reusa al máximo: `RecipientNormalizer` (001), `WebhookEventWorker` (003), `NotificationAudit` particionado (003), HTTP Basic auth (003), Decision/SendResult (004).
- Sin migración destructiva: solo CREATE TABLE + índices. Rollback trivial (DROP TABLE).
