# Implementation Plan: Observabilidad, performance & hardening

**Branch**: `009-observability-perf-hardening` (trabajado en `main`, trunk-based) | **Date**: 2026-05-12

## Summary

Cierre operativo de Phase 10 del roadmap. Seis user stories que dejan la plataforma "lista para entregar a plataforma/SRE": endpoint `/metrics` Prometheus-style (US1), load test reproducible 140 rps × 1h vía k6 en Compose (US2), gates de seguridad bloqueantes en CI con Brakeman ≥ Medium y bundle-audit (US3), documentación de setup containerizado + creación de notificación + runbook (US4), landing público en `/` con descripción del producto (US5), y rediseño visual consistente con Tailwind CDN en todo el panel admin (US6).

**Enfoque técnico**: cero gemas runtime nuevas. Tailwind via CDN (sin Propshaft pipeline). k6 como servicio Compose con perfil `load-test` (no se levanta por default). `/metrics` con queries on-demand a Postgres + HTTP cache 5s. Worker pasa a servicio dedicado en Compose.

## Technical Context

**Language/Version**: Ruby 3.4 / Rails 8.1.3
**Primary Dependencies**: existentes (Devise 5, chartkick, groupdate). Nuevas: ninguna gema runtime. Tailwind via CDN. k6 via imagen `grafana/k6`.
**Storage**: PostgreSQL 17 (sin tablas nuevas; lectura de `dispatch_queue` + `notification_audit` para métricas).
**Testing**: RSpec 7, WebMock, SimpleCov ≥ 90%.
**Target Platform**: contenedores Linux orquestados por Docker Compose. Compatible con Ubuntu 24.04 host (entorno del usuario actual).
**Project Type**: Rails monolith con Hotwire SSR.

## Constitution Check

| Gate | Cumplimiento |
|---|---|
| `mission.md` SLOs (140 rps, < 2s end-to-end) | US2 entrega la evidencia empírica que el SLO afirma. |
| `tech-stack.md` — Postgres-as-queue, sin infra nueva | Sin Kafka/SQS/Redis. k6 es tooling de medición, no runtime. |
| `tech-stack.md` — Observabilidad APM/CloudWatch | Endpoint `/metrics` en formato estándar Prometheus es el adapter local; integración cloud queda fuera de scope (documentada en runbook). |
| `roadmap.md` Phase 10 bullets | Los 5 bullets están cubiertos por las 6 user stories (USx mapea a bullet 1, 2, 3, 4-runbook, 4-docs, +US5/US6 que extienden el bullet de docs hacia UX). |
| ADL-008 (cache Rails) | `/metrics` no cachea en proceso; usa HTTP cache headers (`Cache-Control: max-age=5`). Sin contradicción. |

**Violaciones**: ninguna. US5/US6 amplían el alcance de Phase 10 pero alinean con la métrica de éxito de `mission.md` (descubribilidad + entrega presentable al stakeholder).

## High-Level Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│ docker-compose.yml                                          │
│                                                             │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐               │
│  │  app     │    │  worker  │    │  db      │               │
│  │ (web)    │    │ (queue)  │    │ (pg17)   │               │
│  │ :3000    │    │          │    │ :5432    │               │
│  └────┬─────┘    └────┬─────┘    └────┬─────┘               │
│       │               │               │                     │
│       └───────────────┴───────────────┘                     │
│                                                             │
│  ┌──────────┐  (profile: load-test)                         │
│  │  k6      │  → ejecuta scenario.js → out.json             │
│  │          │                                               │
│  └──────────┘                                               │
└─────────────────────────────────────────────────────────────┘

Rails routes:
  GET /                     → HomeController#show          (público)
  GET /metrics              → MetricsController#show       (HTTP Basic)
  GET /admin/dashboard      → existente                   (Devise)
  ...

Tailwind:
  app/views/layouts/application.html.erb  → <script src="cdn.tailwindcss.com">
  app/views/layouts/admin.html.erb        → mismo CDN + clases utility
```

## Project Structure (archivos a crear/modificar)

```text
app/
├── controllers/
│   ├── home_controller.rb                          [NEW]    US5
│   └── metrics_controller.rb                       [NEW]    US1
├── central/
│   └── observability/
│       └── metrics_collector.rb                    [NEW]    US1 — queries on-demand
├── views/
│   ├── layouts/
│   │   ├── application.html.erb                    [MOD]    US5/US6 — Tailwind CDN + landing layout
│   │   └── admin.html.erb                          [MOD]    US6 — sidebar nav, role-aware, Tailwind
│   ├── home/
│   │   └── show.html.erb                           [NEW]    US5
│   ├── admin/
│   │   ├── dashboard/index.html.erb                [MOD]    US6
│   │   ├── rules/                                  [MOD]    US6
│   │   ├── audits/                                 [MOD]    US6
│   │   ├── blacklist/                              [MOD]    US6
│   │   ├── templates/                              [MOD]    US6
│   │   └── dlq/index.html.erb                      [MOD]    US6
│   └── shared/                                     [NEW]    US6 — partials reutilizables
│       ├── _table.html.erb
│       ├── _flash.html.erb
│       ├── _form_errors.html.erb
│       └── _sidebar.html.erb
config/
├── routes.rb                                       [MOD]    US1/US5 — root + /metrics
└── initializers/
    └── metrics_auth.rb                             [NEW]    US1 — HTTP Basic credentials
docker/
├── Dockerfile                                      [MOD si existe / NEW]   US4 — slim Ruby 3.4 image
└── compose/
    └── k6/
        └── scenario.js                             [NEW]    US2
docker-compose.yml                                  [MOD]    US4 — app/worker/db/k6
bin/
├── load_report                                     [NEW]    US2 — parser de k6 JSON → markdown
docs/
└── runbook.md                                      [NEW]    US4
README.md                                           [MOD]    US4 — Setup con Docker, probar, crear notif
.github/workflows/
└── ci.yml                                          [MOD]    US3 — Brakeman/bundle-audit como fail
.brakeman.ignore                                    [NEW si requerido]   US3
specs/009-observability-perf-hardening/
├── load/
│   └── scenario.js                                 [NEW]    US2 — k6 source
├── reports/
│   └── load-test-<fecha>.md                        [GENERATED]  US2
├── plan.md
├── research.md
├── data-model.md                                   (mínimo — sin tablas nuevas)
├── contracts/
│   ├── metrics-endpoint.md                         [NEW]    US1
│   └── home-page.md                                [NEW]    US5
└── quickstart.md
spec/
├── requests/
│   ├── metrics_controller_spec.rb                  [NEW]    US1
│   └── home_controller_spec.rb                     [NEW]    US5
├── central/
│   └── observability/
│       └── metrics_collector_spec.rb               [NEW]    US1
└── system/
    └── admin_visual_consistency_spec.rb            [NEW]    US6 — capybara checks
```

## Phasing dentro de la feature

1. **Setup**: Docker Compose con servicios app/worker/db + Tailwind CDN en layouts (foundational para todo lo demás).
2. **US1** (P1): `/metrics` endpoint + collector + auth.
3. **US2** (P1): k6 scenario + parser de reporte + ejecución de baseline.
4. **US3** (P2): CI gate Brakeman/bundle-audit.
5. **US4** (P2): docs (README + runbook).
6. **US5** (P2): Home `/` + partials del landing.
7. **US6** (P3): rediseño visual del admin (último porque depende de que el resto esté estable).
8. **Polish**: integration tests visuales, ADLs nuevos, roadmap → DONE, Anexo A update.

## Risks & Mitigations

| Riesgo | Probabilidad | Mitigación |
|---|---|---|
| Tailwind CDN cambia API o se cae | Baja | Documentado como trade-off. Migración a Tailwind precompilado documentada en research.md como ruta de salida. |
| Load test 140 rps en máquina local satura host | Media | k6 corre como container con resource limits. Documentar specs mínimas de máquina; si no se llega a 140, reportar como FAIL con explicación, no inflar números. |
| Rediseño admin rompe tests system existentes | Media | Tests usan selectores semánticos (data-*) cuando es posible. Refactor incremental por vista, no big-bang. |
| `/metrics` queries impactan performance en prod | Baja | HTTP cache 5s + queries indexadas + scrape interval recomendado ≥ 15s. Documentado en runbook. |
| CI gate bloqueante introduce friction en PRs legítimos | Media | Mecanismo de ignore con justificación versionada (`.brakeman.ignore`). Documentado en runbook. |

## Complexity Tracking

No hay violaciones de constitution. La complejidad agregada (US5/US6) es UX, no arquitectónica.

## Out of Scope (reafirmado del spec)

- Integración real con CloudWatch/Datadog/NewRelic.
- Tracing distribuido.
- Profiling de queries (bullet).
- Migración a Tailwind precompilado.
- Rediseño de vistas públicas más allá del landing.
