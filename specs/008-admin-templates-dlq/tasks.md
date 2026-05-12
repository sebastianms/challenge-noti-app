# Tasks — 008-admin-templates-dlq

**Status**: Completado
**Branch**: `main` (trunk-based)

Convenciones: `[P]` paralelizable (archivos distintos), `[USx]` user story owner.

---

## Setup

- [x] T001 Migration `db/migrate/20260513000001_create_notification_templates.rb` (tabla con UNIQUE `(notification_type, locale)`).
- [x] T002 Migration `db/migrate/20260513000002_add_discarded_to_dispatch_queue.rb` (DROP + ADD CHECK incluyendo `discarded`).
- [x] T003 Extender `Admin::RoleAuthorizer::PERMISSIONS` con `:templates` (admin, product) y `:dlq` (admin, engineering) en `app/policies/admin/role_authorizer.rb`.
- [x] T004 Routes: `resources :templates` (con member `preview`) y `resources :dlq, only: [:index]` con `member :retry, :discard` y `collection :bulk_retry` en `config/routes.rb`.

## Foundational

- [x] T005 Model `app/models/notification_template.rb` con validations + callbacks `after_save`/`after_destroy → TemplateCache.invalidate`.
- [x] T006 Factory `spec/factories/notification_templates.rb`.
- [x] T007 Spec model en `spec/models/notification_template_spec.rb` (validations, callback dispara invalidate).

## US1 — Editor de templates con preview

- [x] T008 [P] [US1] `app/central/templates/template_interpolator.rb` — `interpolate(string, context) → {result, missing}`.
- [x] T009 [P] [US1] Spec `spec/central/templates/template_interpolator_spec.rb` — happy, missing keys, edge (string vacío, sin vars).
- [x] T010 [US1] `app/central/templates/template_cache.rb` — wrapper `Rails.cache.fetch(key, expires_in: 5.minutes)` + `invalidate(type, locale)`.
- [x] T011 [US1] `app/central/templates/template_resolver.rb` — `title_for/body_for/digest_for(type:, locale:, ctx:)`, usa cache, devuelve `nil` si no hay override.
- [x] T012 [US1] Spec resolver `spec/central/templates/template_resolver_spec.rb` (override presente, ausente, cache hit, invalidación tras edición).
- [x] T013 [US1] Modificar `app/central/abstract_notification.rb` para consultar `TemplateResolver` en `title/body/digest_template` antes de delegar a la subclase.
- [x] T014 [US1] Spec en `spec/central/abstract_notification_spec.rb` extendido: con override usa DB; sin override usa Ruby (regresión Phase 2).
- [x] T015 [US1] `app/controllers/admin/templates_controller.rb` < `BaseController` con `controller_section = :templates`. Acciones: `index, new, create, edit, update, destroy, preview`.
- [x] T016 [US1] Views: `app/views/admin/templates/index.html.erb`, `new.html.erb`, `edit.html.erb`, `_form.html.erb`, `_preview.html.erb` (turbo-frame).
- [x] T017 [US1] Spec `spec/requests/admin/templates_controller_spec.rb` — CRUD, preview con missing key, gating product OK, engineering 403, redirect-to-login.

## US2 — Operaciones gestiona la DLQ

- [x] T018 [P] [US2] `app/central/admin/dlq_query.rb` — `grouped_by_reason` retorna array de `{reason_class, count, items_preview}`; helper `reason_class_for(error_string)` con `split_part`/fallback `'Unknown'`.
- [x] T019 [P] [US2] Spec `spec/central/admin/dlq_query_spec.rb` (agrupación correcta, `Unknown` para errores sin clase parseable, cap de items_preview).
- [x] T020 [US2] `app/central/admin/dlq_retrier.rb` — `call(job, by:)` individual y `bulk_call(reason:, by:, cap: 500)` con `id IN (SELECT … FOR UPDATE SKIP LOCKED LIMIT 500)` y audit consolidado.
- [x] T021 [US2] Spec `spec/central/admin/dlq_retrier_spec.rb` — individual ok, bulk respeta cap, audit con `count` y `reason_filter`, transaccionalidad (rollback si falla audit).
- [x] T022 [P] [US2] `app/central/admin/dlq_discarder.rb` — `call(job, reason:, by:)` con validación de motivo presente.
- [x] T023 [P] [US2] Spec `spec/central/admin/dlq_discarder_spec.rb` — descarte ok, motivo vacío → `ArgumentError`/`Result.invalid`.
- [x] T024 [US2] `app/controllers/admin/dlq_controller.rb` < `BaseController` con `controller_section = :dlq`. Acciones: `index, retry, bulk_retry, discard`.
- [x] T025 [US2] View `app/views/admin/dlq/index.html.erb` (grupos por motivo con counts, expand para ver items, botones retry/discard, form bulk_retry).
- [x] T026 [US2] Spec `spec/requests/admin/dlq_controller_spec.rb` — retry individual, bulk con cap, discard con motivo vacío → 422, gating engineering OK / product 403.

## Polish

- [x] T027 Integration spec `spec/integration/admin_ui_templates_dlq_spec.rb` — walkthrough end-to-end cubriendo los 7 escenarios de `quickstart.md`.
- [x] T028 ADL `.design-logs/ADL-013-template-override-resolver.md` (cache + fallback Ruby; rationale interpolator propio vs Liquid).
- [x] T029 ADL `.design-logs/ADL-014-dlq-bulk-retry-cap.md` (cap 500 + `FOR UPDATE SKIP LOCKED` + transaccionalidad).
- [x] T030 Actualizar `README.md`: agregar rutas `/admin/templates` y `/admin/dlq` a la tabla, permisos por rol, mención de Mustache-lite.
- [x] T031 Actualizar `specs/roadmap.md` Phase 9 → `[DONE]` con DoD verificado.
- [x] T032 Actualizar `MiniCentral De Notificaciones.md` Anexo A (features +1, ejemplos suite, ADLs 14).
- [x] T033 Block checkpoint: RuboCop 0 warnings, Brakeman, RSpec ≥ 90% coverage, Deckard review, commits por bloque, push.
