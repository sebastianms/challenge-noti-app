# Tasks — 006-admin-dashboard-rules

**Feature**: UI Admin — Dashboard + Reglas (Phase 7)
**Status**: Pending
**Created**: 2026-05-11

Convenciones:
- `[ ]` pendiente · `[/]` en progreso · `[x]` hecho · `[-]` deferido
- `[P]` paralelo (archivos independientes, sin deps)
- `[USn]` user story label (omitido en Setup/Foundational/Polish)

---

## Setup (S)

- [ ] T001 Agregar gems `devise ~> 4.9`, `chartkick ~> 5.1`, `groupdate ~> 6.4` al `Gemfile` y `bundle install`
- [ ] T002 [P] Generar instalación de Devise: `bin/rails g devise:install` (mailer config en `config/environments/development.rb`; en este proyecto sin SMTP basta con `config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }`)
- [ ] T003 [P] Configurar Devise: `config.paranoid = true`, `config.maximum_attempts = 5`, `config.unlock_in = 10.minutes`, `config.password_length = 12..128`, `config.mailer_sender = "noreply@noti-central.local"` en `config/initializers/devise.rb`
- [ ] T004 [P] Importmap pin para Chart.js: `bin/importmap pin chartkick chart.js` y `import "chartkick"; import "Chart.bundle"` en `app/javascript/application.js`
- [ ] T005 [P] Crear `config/initializers/mock_data_feature.rb` con `Rails.application.config.allow_mock_data_feature = ENV.fetch("ALLOW_MOCK_DATA_FEATURE", "true") != "false"`

## Foundational (F) — bloquean cualquier US

- [ ] T006 Migración `bin/rails g devise admin_user role:string` → renombrar timestamp a anterior a la hora actual; **antes de `db:migrate`** agregar manualmente `t.string :role, null: false` + extras de lockable (`failed_attempts`, `unlock_token`, `locked_at`) + trackable. Añadir índices únicos en `unlock_token` y `reset_password_token`.
- [ ] T007 Migración `add_role_check_to_admin_users`: `ALTER TABLE admin_users ADD CONSTRAINT admin_users_role_chk CHECK (role IN ('admin','product','support','engineering'))`.
- [ ] T008 Migración `create_rule_changes`: tabla con `notification_rule_id` (FK SET NULL), `admin_user_id` (FK RESTRICT NOT NULL), `action` (CHECK IN), `before` jsonb, `after` jsonb, `changed_at` (default `clock_timestamp()`). 3 índices según data-model.
- [ ] T009 [P] Modelo `app/models/admin_user.rb`: Devise modules + `validates :role, inclusion: { in: %w[admin product support engineering] }` + `validates :password, length: { minimum: 12 }` (cuando se setea).
- [ ] T010 [P] Modelo `app/central/decisioning/rule_change.rb`: `belongs_to :notification_rule, optional: true`, `belongs_to :admin_user`, validaciones de invariantes (`action`/`before`/`after` coherentes).
- [ ] T011 [P] Servicio `app/policies/admin/role_authorizer.rb` con `PERMISSIONS` hash y `self.allow?(role, section:)`.
- [ ] T012 Configurar `devise_for :admin_users, path: "admin", controllers: { sessions: "admin/sessions" }, skip: [:registrations]` + `namespace :admin do ... end` en `config/routes.rb` con resources `dashboard`, `rules` (con `member { get :history }`), `mock_data` (only: [:create]).
- [ ] T013 [P] `app/controllers/admin/base_controller.rb`: `before_action :authenticate_admin_user!`, `before_action :authorize_section!` con helper `controller_section` (devuelto por cada subclase). Render `errors/forbidden` con 403.
- [ ] T014 [P] Layout `app/views/layouts/admin.html.erb` con menú lateral que itera permitidos del rol (`%w[dashboard rules].select { |s| RoleAuthorizer.allow?(...) }`).
- [ ] T015 [P] Vistas error `app/views/errors/forbidden.html.erb` y `not_found.html.erb`.
- [ ] T016 [P] Factory `spec/factories/admin_users.rb` con traits `:admin`, `:product`, `:support`, `:engineering`.
- [ ] T017 [P] Factory `spec/factories/rule_changes.rb` con traits `:created`, `:updated`, `:deleted`.
- [ ] T018 Spec `spec/policies/admin/role_authorizer_spec.rb` — matriz exhaustiva 4 roles × 3 secciones.
- [ ] T019 [P] Spec `spec/models/admin_user_spec.rb` — validaciones (email único, role en whitelist, password ≥ 12).
- [ ] T020 [P] Spec `spec/central/decisioning/rule_change_spec.rb` — invariantes action/before/after.

**Checkpoint F**: lint 0 · `rspec` verde (matriz + modelos) · commit `feat(006-admin-dashboard-rules/foundational): devise + role_authorizer + rule_changes`.

---

## US1 — Auth + roles (P1)

- [ ] T021 [P] [US1] `app/controllers/admin/sessions_controller.rb` extiende `Devise::SessionsController`, override `respond_to_on_destroy` para redirect a `/admin/login` con flash; usa `flash[:notice]` genérico (Devise paranoid se encarga del mensaje).
- [ ] T022 [P] [US1] Vista `app/views/admin/sessions/new.html.erb` con form simple (email, password, remember me).
- [ ] T023 [US1] Spec request `spec/requests/admin/sessions_controller_spec.rb`: login exitoso (302 → dashboard); login fallido (200 form + mensaje genérico); lockable tras 5 intentos (423 / redirect con mensaje); logout DELETE invalida sesión.
- [ ] T024 [US1] Spec request `spec/requests/admin/role_gates_spec.rb`: matriz de respuestas por rol sobre `/admin/dashboard`, `/admin/rules`, `/admin/mock_data` (sin invocar generación todavía, solo `before_action`).

**Checkpoint US1**: lint 0 · rspec verde · commit `feat(006-admin-dashboard-rules/us1): devise sessions + role gates`.

---

## US2 — Dashboard (P1)

- [ ] T025 [P] [US2] Servicio `app/services/admin/dashboard_metrics.rb` con `#snapshot` (cache 30s sobre `volume`, `filter_rate`, `error_rate`; queue depth en vivo).
- [ ] T026 [P] [US2] Controller `app/controllers/admin/dashboard_controller.rb < Admin::BaseController` con `controller_section = :dashboard` y `@snapshot = Admin::DashboardMetrics.new.snapshot`.
- [ ] T027 [US2] Vista `app/views/admin/dashboard/index.html.erb` con 4 secciones: `bar_chart` volumen, `pie_chart` filter_rate, dos contadores grandes (queue/dlq), tabla error_rate. Renderizar `_mock_data_button` partial (vacío hasta US4).
- [ ] T028 [P] [US2] Spec `spec/services/admin/dashboard_metrics_spec.rb` con seeds y aserciones sobre cada clave del Hash (estado vacío, con datos, cache hit).
- [ ] T029 [US2] Spec request `spec/requests/admin/dashboard_controller_spec.rb` con login como product/admin/engineering/support y verificación de 200 + presencia de los 4 bloques.

**Checkpoint US2**: lint 0 · rspec verde · commit `feat(006-admin-dashboard-rules/us2): dashboard metrics + KPIs view`.

---

## US3 — CRUD reglas + audit trail (P1)

- [ ] T030 [US3] Controller `app/controllers/admin/rules_controller.rb < Admin::BaseController`: index/new/create/edit/update/destroy/history. `controller_section = :rules`. Cada mutation envuelta en transacción + `RuleChange.create!` con diff.
- [ ] T031 [P] [US3] Helper `app/helpers/admin/rules_helper.rb#diff_row(before, after, key)` para render de `history.html.erb`.
- [ ] T032 [P] [US3] Vistas `index.html.erb` (lista con link history), `_form.html.erb` (todos los campos validados), `new.html.erb`, `edit.html.erb`, `history.html.erb` (timeline con diff campo-a-campo).
- [ ] T033 [P] [US3] Spec request `spec/requests/admin/rules_controller_spec.rb`: CRUD completo + history listing + invalidación cache verificable (mock `RuleCache.invalidate`).
- [ ] T034 [P] [US3] Spec `spec/services/admin/rule_change_recording_spec.rb`: cada acción persiste 1 fila con before/after correctos y `admin_user_id` actual.
- [ ] T035 [US3] Spec autorización: `product` ✓, `support`/`engineering` → 403 en todas las acciones de rules.

**Checkpoint US3**: lint 0 · rspec verde · commit `feat(006-admin-dashboard-rules/us3): rules CRUD + history`.

---

## US4 — Mock data (P2)

- [ ] T036 [P] [US4] Módulo `app/services/admin/mock_data_feature.rb` con `self.enabled?` (lee `Rails.application.config.allow_mock_data_feature`).
- [ ] T037 [P] [US4] Servicio `app/services/admin/mock_data_generator.rb` con `#call` retornando `Result`. Idempotencia según research R7 (find_or_create_by reglas, insert_all unique_by blacklist).
- [ ] T038 [US4] Controller `app/controllers/admin/mock_data_controller.rb < Admin::BaseController`: `controller_section = :mock_data`. `create` chequea `MockDataFeature.enabled?` (sino 403) + ejecuta `MockDataGenerator.new.call` + flash + redirect a referrer (default dashboard).
- [ ] T039 [P] [US4] Partial `app/views/admin/shared/_mock_data_button.html.erb` con `if MockDataFeature.enabled? && current_admin_user&.role == "admin"` → `button_to "Generar Data Mock", admin_mock_data_path, method: :post`.
- [ ] T040 [US4] Insertar `<%= render "admin/shared/mock_data_button" %>` en `dashboard/index.html.erb` y `rules/index.html.erb`.
- [ ] T041 [P] [US4] Spec `spec/services/admin/mock_data_generator_spec.rb`: ejecuta dos veces, verifica idempotencia de reglas/blacklist y acumulación de audits/queue.
- [ ] T042 [US4] Spec request `spec/requests/admin/mock_data_controller_spec.rb`: 403 con flag off · 403 si rol ≠ admin · 303 + flash success en happy path · botón presente/ausente según flag (request al dashboard).

**Checkpoint US4**: lint 0 · rspec verde · commit `feat(006-admin-dashboard-rules/us4): mock data generator + feature flag`.

---

## Polish (PL)

- [ ] T043 [P] Seeds `db/seeds.rb` agregar bloque idempotente: si `Rails.env.development?` y no hay admin_users, crear 4 con un rol cada uno (passwords en log de stdout).
- [ ] T044 [P] Spec integración `spec/integration/admin_ui_spec.rb`: walkthrough US1→US2→US3→US4 con 1 sólo admin loggeado.
- [ ] T045 [P] ADL-011 en `.design-logs/`: "Devise + admin_users(role) en lugar de HTTP Basic + ENV para Phase 7". Documentar alternativas, consecuencias, link a research.md R1/R2.
- [ ] T046 [P] README: agregar sección "Panel admin (UI)" con cómo crear usuario seed, login, lista de rutas, mención al flag `ALLOW_MOCK_DATA_FEATURE`.
- [ ] T047 Roadmap: marcar Phase 7 `[DONE]` con bullets reales.
- [ ] T048 Benchmark SC-002: crear `script/benchmark_dashboard.rb` que siembra 10k audits y mide tiempo de `DashboardMetrics#snapshot` (assert < 2s p95).
- [ ] T049 Smoke completo del bloque: `rubocop`, `rspec --format documentation`, `brakeman --no-pager`, `bundler-audit`. Cobertura ≥ 99% global, ≥ 95% en módulos nuevos.
- [ ] T050 Anexo A de `MiniCentral De Notificaciones.md`: actualizar A.4 (3 situaciones nuevas: Devise + roles, Chartkick demo-friendly, MockData con defensa en profundidad), A.5 (métricas finales fase 7), A.7 si corresponde.

**Checkpoint Polish**: smoke verde · ADL-011 publicado · commits separados por responsabilidad · `git push origin main`.

---

## Resumen

- **Total**: 50 tasks
- **Bloqueantes**: Setup (5) → Foundational (15) → US en paralelo lógico (US1 4 tasks · US2 5 · US3 6 · US4 7) → Polish (8)
- **Tests-first**: T018, T019, T020 en Foundational; cada US incluye sus specs antes/junto al código
- **ADLs nuevos esperados**: 1 (ADL-011)
- **Migraciones nuevas**: 3 (devise_create_admin_users, add_role_check, create_rule_changes)
