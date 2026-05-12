# Tasks — 009-observability-perf-hardening

**Status**: En progreso
**Branch**: `main` (trunk-based)

Convenciones: `[P]` paralelizable (archivos distintos), `[USx]` user story owner.

---

## Setup

- [x] T001 Crear `Dockerfile` (o actualizar si existe) con Ruby 3.4-slim base + apt deps (libpq-dev, build-essential) + bundle install + COPY app + EXPOSE 3000.
- [x] T002 Crear/actualizar `docker-compose.yml` con servicios `app` (web :3000), `worker` (cmd `bin/rails worker:run[10,2]`), `db` (postgres:17 con healthcheck), `test` (preservar el existente), `k6` (image `grafana/k6` bajo perfil `load-test`).
- [x] T003 Crear `.dockerignore` (excluir `tmp/`, `log/`, `node_modules/`, `.git`).
- [x] T004 [P] Crear `config/initializers/metrics_auth.rb` con lectura de ENV `METRICS_BASIC_AUTH_USER`/`METRICS_BASIC_AUTH_PASSWORD` y constante `MetricsAuth::CREDENTIALS_PRESENT`.
- [x] T005 [P] Agregar Tailwind CDN script tag a `app/views/layouts/application.html.erb` y a `app/views/layouts/admin.html.erb`. Verificar que ambos cargan sin error.

## Foundational

- [x] T006 Crear partial `app/views/shared/_flash.html.erb` con `data-flash-container` y clases Tailwind para success/notice/alert.
- [x] T007 Crear partial `app/views/shared/_form_errors.html.erb` (renderiza `object.errors.full_messages` con estilo consistente).
- [x] T008 Crear partial `app/views/shared/_table.html.erb` (acepta headers + rows blocks; clases base `admin-table`).
- [x] T009 Crear partial `app/views/shared/_sidebar.html.erb` con secciones Operación/Reglas/Auditoría, role-aware vía `RoleAuthorizer.allowed?(current_admin_user.role, :section)`. Resalta sección activa con `data-active`.
- [x] T010 Crear helper `app/helpers/admin/navigation_helper.rb` con `active_section?(section)` y `nav_link_to(label, path, section:)`.
- [x] T011 Spec `spec/helpers/admin/navigation_helper_spec.rb`.

## US1 — Endpoint /metrics (P1)

- [x] T012 [P] [US1] `app/central/observability/metrics_collector.rb` — clase con métodos `queue_depth`, `dlq_size`, `events_ingested_24h`, `dispatch_errors_by_class`, `bounce_rate_5m`, `webhook_lag_seconds`. Todas con queries directas a AR.
- [x] T013 [P] [US1] Spec `spec/central/observability/metrics_collector_spec.rb` — verifica cada query con factories.
- [x] T014 [US1] `app/central/observability/prometheus_formatter.rb` — `format(metrics_hash) → String` Prometheus text exposition.
- [x] T015 [US1] Spec `spec/central/observability/prometheus_formatter_spec.rb` — gauges simples, gauges con labels, multi-label.
- [x] T016 [US1] `app/controllers/metrics_controller.rb` con auth Basic runtime via `authenticate_or_request_with_http_basic`, action `show` que llama collector + formatter, set `Cache-Control: public, max-age=5`, rescue `ActiveRecord::ConnectionNotEstablished` → 503.
- [x] T017 [US1] Route `get "/metrics" => "metrics#show"` en `config/routes.rb`.
- [x] T018 [US1] Spec `spec/requests/metrics_controller_spec.rb` — 200 con auth + formato, 401 sin auth, 503 sin ENV configurada, header cache presente, performance < 100ms con 10k filas.

## US2 — Load test 140 rps × 1h (P1)

- [x] T019 [P] [US2] `specs/009-observability-perf-hardening/load/scenario.js` — k6 scenario: constant arrival rate 140 rps, duration configurable (default 1h), POST a `/internal/ingest`.
- [x] T020 [P] [US2] Decisión: `POST /internal/ingest` habilitada solo con `ALLOW_LOAD_TEST_INGEST=1` + credenciales `LOAD_TEST_BASIC_AUTH_*`. Docker Compose expone las vars via interpolación de host. `config.hosts << "app"` agregado en development para permitir requests desde red Docker.
- [x] T021 [US2] Controller `app/controllers/internal/ingest_controller.rb` + spec request básico (201/400/401/503).
- [x] T022 [P] [US2] `bin/load_report` — parsea k6 summary JSON (formato flat: `http_req_duration["p(95)"]`, `http_req_failed["value"]`, `iterations["count"]`) → markdown con tabla + verdict PASS/FAIL.
- [x] T023 [P] [US2] Spec `spec/bin/load_report_spec.rb` — 3 fixtures (pass/fail/interrupted) → output y exit code esperados.
- [x] T024 [US2] Baseline 5 min a 140 rps: 34609 iter, 0% error rate, p95=2017ms (FAIL en latencia — entorno dev local, proceso único). Reporte en `specs/009-.../reports/load-test-baseline-2026-05-12.md`.

## US3 — CI gates Brakeman + bundle-audit (P2)

- [x] T025 [US3] Modificar `.github/workflows/ci.yml`: step `brakeman` con `bundle exec brakeman --no-pager --confidence-level 2 --exit-on-warn`. Step `bundle-audit` con `bundle exec bundle-audit check --update`. Ambos sin `continue-on-error`.
- [x] T026 [P] [US3] Generar `config/brakeman.ignore` inicial (vacío o con findings actuales si los hay) con `bundle exec brakeman -I` interactivo. Commitear.
- [x] T027 [US3] Sección en README explicando: cómo correr Brakeman local (`docker compose exec app bundle exec brakeman`), cómo aceptar un falso positivo (editar `config/brakeman.ignore` con note + fingerprint).

## US4 — Docs setup Docker + crear notif + runbook (P2)

- [x] T028 [US4] Reescribir sección "Setup" del README como "Setup con Docker": pre-requisitos (Docker ≥ 24, puertos 3000/5432 libres), comandos copy-paste-ables desde `git clone` hasta `docker compose exec app bin/rspec` verde.
- [x] T029 [P] [US4] Sección "Probar la aplicación" en README: login admin (con seeds), disparar notificación via console, verificar audit, ver dashboard. Comandos + outputs esperados.
- [x] T030 [P] [US4] Sección "Crear una notificación nueva" en README: pasos exactos para FooNotification (clase nueva + opcional regla + opcional template), todo via `docker compose exec`.
- [x] T031 [US4] `docs/runbook.md` con secciones: (a) DLQ saturada, (b) Bounce rate alto, (c) Sendgrid down, (d) Partición de auditoría faltante, (e) Alarmas recomendadas (umbrales sugeridos + rationale). Cada escenario: síntomas, diagnóstico, remediación, criterios de escalación.

## US7 — Tour de la aplicación (P2)

- [x] T031b [P] [US7] `docs/app-tour.md` con sección por cada área del panel: Home, Dashboard, Reglas, Auditoría, Blacklist, Templates, DLQ. Cada sección: propósito (2-3 líneas), rol con acceso, acción típica con pasos usando datos de seed, qué observar en pantalla.
- [ ] T031c [US7] Agregar link a `docs/app-tour.md` (URL absoluta al repo GitHub) en el footer de `app/views/home/show.html.erb`. (Bloqueado por US5 — la view no existe aún)

## US5 — Home page pública (P2)

- [ ] T032 [P] [US5] `app/controllers/home_controller.rb` con action `show`, sin auth, sin layout admin.
- [ ] T033 [P] [US5] `app/views/home/show.html.erb` con hero, flujo numerado 4 pasos, tabla de endpoints públicos, footer con link repo. CTA condicional según `admin_user_signed_in?`.
- [ ] T034 [US5] Route `root "home#show"` en `config/routes.rb` (reemplaza/agrega). Verificar que no rompe redirect a `/admin/login` post-logout.
- [ ] T035 [US5] Spec `spec/requests/home_controller_spec.rb` — 200 sin sesión, 200 con sesión admin (CTA distinto), sin redirect, < 100ms.

## US6 — Diseño visual consistente (P3)

- [ ] T036 [US6] Refactor `app/views/layouts/admin.html.erb` para usar `_sidebar.html.erb` y `_flash.html.erb`. Eliminar nav inline existente.
- [ ] T037 [P] [US6] Refactor `app/views/admin/dashboard/index.html.erb` con clases Tailwind consistentes (cards, grid, chart wrappers).
- [ ] T038 [P] [US6] Refactor `app/views/admin/rules/` (index, _form, edit, new) con `_table` + `_form_errors`.
- [ ] T039 [P] [US6] Refactor `app/views/admin/audits/` con `_table` + filtros estilizados.
- [ ] T040 [P] [US6] Refactor `app/views/admin/blacklist/` con `_table` + `_form_errors`.
- [ ] T041 [P] [US6] Refactor `app/views/admin/templates/` (index, _form, _preview, edit, new) con `_table` + `_form_errors`.
- [ ] T042 [P] [US6] Refactor `app/views/admin/dlq/index.html.erb` con grupos colapsables + `btn-danger` para discard.
- [ ] T043 [US6] System spec `spec/system/admin_visual_consistency_spec.rb` — recorre las 6 vistas, verifica `data-admin-sidebar`, `admin-table`, `btn-danger`, `data-flash-container`.

## Polish

- [ ] T044 Integration spec `spec/system/observability_polish_walkthrough_spec.rb` — walkthrough end-to-end cubriendo E1-E9 de `quickstart.md` (los que sean automatizables; E1/E3/E5/E9 cronometrados manualmente quedan documentados).
- [ ] T045 ADL `.design-logs/ADL-015-metrics-endpoint-prometheus.md` — formato exposition, queries on-demand, auth separada, HTTP cache.
- [ ] T046 ADL `.design-logs/ADL-016-tailwind-cdn-admin-design.md` — Tailwind CDN trade-offs, sidebar layout, partials compartidos, ruta de salida a precompilado.
- [ ] T047 ADL `.design-logs/ADL-017-docker-compose-primary-dev.md` — Compose como camino primario, servicio worker dedicado, perfil `load-test`.
- [ ] T048 Actualizar `specs/roadmap.md` Phase 10 → `[DONE]` con los 5 bullets verificados + nota de US5/US6 como extensión.
- [ ] T049 Actualizar `MiniCentral De Notificaciones.md` Anexo A (features +1 = 9, ejemplos suite actualizados, ADLs +3 = 17, mención de app-tour.md y runbook.md).
- [ ] T050 Block checkpoint final: RuboCop 0 warnings, Brakeman 0 (con nuevo gate activo), bundle-audit clean, RSpec ≥ 90% coverage, Deckard review, commits por bloque (Setup, Foundational, US1, US2, US3, US4, US5, US6, Polish), push.

---

## Dependencias

- Setup (T001-T005) bloquea **todo**.
- Foundational (T006-T011) bloquea US6 y partes de US5 (que reusan `_flash`, `_sidebar`).
- US1 / US2 / US3 / US4 son independientes entre sí (paralelizables como features).
- US5 depende de Foundational para Tailwind CDN ya cargado pero no de los partials admin.
- US6 depende de Foundational (partials) y conviene hacerla **última** para no rehacer si cambian otras vistas.
- Polish (T044+) requiere todas las US cerradas.

## Notas de execution

- Tests deben pasar **dentro del contenedor app**: `docker compose exec app bin/rspec`.
- Lint dentro del contenedor: `docker compose exec app bundle exec rubocop`.
- Cada User Story cierra con su propio block checkpoint (lint + tests + Deckard + commits + push) — la regla de Phase 9.
