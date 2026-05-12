# Research — 009-observability-perf-hardening

**Fecha**: 2026-05-12

## R1 — Formato y stack del endpoint `/metrics`

**Decisión**: text exposition Prometheus generado a mano (Ruby puro), sin gema `prometheus-client`.

**Rationale**:
- El formato Prometheus text es estable y simple (líneas `metric_name{labels} value`). Ruby puro lo genera en ~30 líneas.
- `prometheus-client` agrega complejidad (registries, multi-process store, gem mantenance) sin valor en un mono-proceso con queries on-demand.
- Mantiene la regla "cero gemas runtime nuevas" del plan.

**Alternativas consideradas**:
| Opción | Pros | Contras | Descartada porque |
|---|---|---|---|
| Gema `prometheus-client` | Estándar, multi-process | Estado in-memory, deps extra | Overkill para 6 métricas on-demand |
| JSON propio | Trivial de generar | Requiere parser custom en el consumidor | Pierde interop con cualquier Prometheus/Grafana futuro |
| StatsD push | Real-time | Requiere agent local (StatsD daemon) | Infra extra contraria a tech-stack.md |

---

## R2 — Cómo computar las métricas

**Decisión**: queries on-demand a Postgres en cada scrape + HTTP cache `Cache-Control: max-age=5, public`.

**Rationale**:
- Sin estado en proceso → no hay race conditions ni deploy resets.
- Tablas `dispatch_queue` y `notification_audit` ya tienen índices apropiados para los COUNTs (status + created_at).
- Cache HTTP 5 s amortiza scrapes agresivos sin comprometer frescura operativa.
- Decidido en `Clarifications` del spec.

**Queries planificadas**:
```sql
-- queue_depth
SELECT COUNT(*) FROM dispatch_queue WHERE status = 'pending';
-- dlq_size
SELECT COUNT(*) FROM dispatch_queue WHERE status = 'failed';
-- events_ingested_total (últimos 24h como proxy de counter; el "total" en Prometheus es un gauge cumulative — aceptamos esta aproximación documentada)
SELECT COUNT(*) FROM notification_events WHERE created_at > NOW() - INTERVAL '24 hours';
-- dispatch_errors_total{class}
SELECT split_part(COALESCE(failed_reason,''), ':', 1) AS class, COUNT(*)
  FROM dispatch_queue WHERE status = 'failed' GROUP BY 1;
-- bounce_rate_5m
SELECT
  SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END)::float /
  NULLIF(COUNT(*), 0)
  FROM notification_audit
  WHERE created_at > NOW() - INTERVAL '5 minutes';
-- webhook_lag_seconds (gauge: max edad de webhook_events.status='pending')
SELECT EXTRACT(EPOCH FROM NOW() - MIN(created_at))
  FROM webhook_events WHERE status = 'pending';
```

**Trade-off documentado**: `events_ingested_total` no es un counter monotónico real (decae con retention). Para la naturaleza de challenge demo es aceptable. Si se migra a counters in-memory en el futuro, la métrica se convierte en counter real sin cambiar el endpoint.

---

## R3 — Auth del endpoint `/metrics`

**Decisión**: HTTP Basic Auth con ENV vars `METRICS_BASIC_AUTH_USER` / `METRICS_BASIC_AUTH_PASSWORD`, separados de los del panel admin (Devise).

**Rationale**:
- Prometheus / scrapers no manejan flujos de sesión Devise. HTTP Basic es el estándar de facto para `/metrics` privados.
- Separar las credenciales evita acoplar el rotation de password del operador humano con la config del scraper.
- Ya hay precedente en el proyecto (`AUDIT_BASIC_AUTH_*` se usó hasta Phase 7).

**Alternativas**:
- Token en header (`Authorization: Bearer ...`) — equivalente en práctica pero menos estándar para Prometheus.
- Allowlist por IP — frágil, depende de network policies que no aplicamos en demo.

---

## R4 — Tailwind via CDN vs precompilado

**Decisión**: Tailwind via CDN (`<script src="https://cdn.tailwindcss.com">`) en `application.html.erb` y `admin.html.erb`.

**Rationale**:
- Cero build step. No requiere Node, Yarn, Tailwind CLI, ni cambios a Propshaft.
- Permite iterar el diseño sin reiniciar el contenedor app.
- Trade-off aceptado: dependencia de internet en dev (insignificante), payload algo mayor que purgado (irrelevante en demo).

**Migración futura documentada**: si el proyecto crece, ruta a Tailwind precompilado vía `tailwindcss-rails` gem o ESBuild. ADL futuro lo cubriría.

**Alternativas**:
| Opción | Pros | Contras | Descartada porque |
|---|---|---|---|
| Bootstrap CDN | Componentes pre-hechos | Look más rígido, menos modern | Tailwind da más control con esfuerzo similar |
| CSS custom | Sin deps | Inventar grid, spacing, colores desde cero | Mucho tiempo para look profesional |
| Tailwind precompilado | Bundle minimal | Build step + JS toolchain | Sobre-ingeniería para challenge |

---

## R5 — Load testing tooling

**Decisión**: k6 (`grafana/k6` Docker image) como servicio adicional en `docker-compose.yml` bajo perfil `load-test`. Output JSON parseado por `bin/load_report` (Ruby) → markdown.

**Rationale**:
- k6 es industry standard para load tests, scripts en JS (legible), single binary distribuido como image oficial.
- Perfil Compose evita levantarlo siempre; `docker compose --profile load-test up k6` lo dispara.
- Output JSON estructurado facilita parsing determinista.

**Alternativas**:
| Opción | Pros | Contras | Descartada porque |
|---|---|---|---|
| vegeta | Binary mínimo | Requiere CLI host o container custom | k6 tiene image oficial, Compose-friendly |
| Ruby threads + Net::HTTP | Cero deps | GIL limita concurrencia real, métricas manuales | No confiable para 140 rps sostenidos |
| Apache Bench | Trivial | No soporta scenarios, solo flat rps | Necesitamos endpoint + body JSON variable |

**Estructura del scenario**: 140 rps constantes durante 1h, POST a un endpoint de ingesta (a definir si exponemos `/ingest` o usamos un task console). Métricas: `http_req_duration` p50/p95/p99, `http_req_failed`, `iterations`.

**Reporte**: `bin/load_report specs/009-.../load/out.json > specs/009-.../reports/load-test-YYYYMMDD-HHMM.md`.

---

## R6 — Brakeman bloqueante en CI

**Decisión**: `bundle exec brakeman --no-pager --confidence-level 2 --exit-on-warn` en el job de CI. Confidence-level 2 = Medium+. Ignores en `config/brakeman.ignore` (formato JSON nativo de Brakeman, no `.brakeman.ignore`).

**Rationale**:
- Brakeman tiene 3 niveles: High (1), Medium (2), Weak (3). Bloqueamos en 2+ para evitar el ruido de Weak (frecuentes falsos positivos en helpers).
- `--exit-on-warn` hace que warnings ≥ confidence definido devuelvan exit 1, fallando CI.
- `config/brakeman.ignore` se genera con `brakeman -I` y se commitea — cada entry tiene fingerprint + note del developer.

**Alternativa descartada**: bloqueo en High solamente. Es demasiado permisivo — varios CVEs reales (SSRF, mass assignment) reportan en Medium.

---

## R7 — bundle-audit bloqueante en CI

**Decisión**: `bundle exec bundle-audit check --update`. Sin ignores por defecto. Si aparece falso positivo, agregar `--ignore CVE-XXXX-XXXX` con comentario en el step del workflow.

**Rationale**: CVEs en gems se publican raramente y casi siempre son accionables. Mejor forzar acción explícita ante cada uno que normalizar ignores.

---

## R8 — Worker como servicio Compose

**Decisión**: agregar servicio `worker` en `docker-compose.yml` que ejecuta `bin/rails worker:run[10,2]` y depende de `db` healthy.

**Rationale**:
- Demo más realista — la cola se procesa sola.
- Refleja deploy productivo (ASG con workers separados).
- Logs separados por servicio facilitan debug.

**Detalle**: mismo image que `app`, command distinto. `restart: unless-stopped`. Sin port mapping. Volumen `./:/rails` para hot reload del código (development).

---

## R9 — Layout del panel admin (US6)

**Decisión**: sidebar lateral fija (`md:w-64`), nav vertical con secciones agrupadas por dominio:

```text
┌──────────┬───────────────────────────────────┐
│ LOGO     │ Header: usuario actual + logout   │
│          ├───────────────────────────────────┤
│ Operación│                                   │
│ - Dash   │ Content area                      │
│ - DLQ    │                                   │
│          │                                   │
│ Reglas   │                                   │
│ - Rules  │                                   │
│ - BL     │                                   │
│ - Tmpl   │                                   │
│          │                                   │
│ Auditoría│                                   │
│ - Audits │                                   │
└──────────┴───────────────────────────────────┘
```

**Rationale**:
- Sidebar es estándar admin, deja más espacio horizontal para tablas (vs topnav que sacrifica vertical).
- Agrupación semántica reduce carga cognitiva ante 7+ secciones.
- Links se renderizan solo si `RoleAuthorizer.allowed?(current_admin_user.role, section)` — single source of truth, sin duplicar la matriz.

**Alternativa descartada**: topnav con dropdowns. Más compacto en mobile pero peor para escaneo rápido en desktop (uso primario admin).

---

## R10 — Home `/` content

**Decisión**: server-rendered ERB simple con secciones: hero (título + tagline), flow diagram (lista numerada con iconos, no SVG), endpoints públicos table, footer con link al repo.

**Rationale**:
- ERB + Tailwind sin Stimulus controllers — landing es estático, sin interactividad.
- Lista numerada > SVG diagram: más fácil de mantener, accesible, sin dependencias gráficas.
- CTA condicional (login vs ir-al-dashboard) usa el helper `admin_user_signed_in?` de Devise.

---

## R11 — Tests visuales (US6)

**Decisión**: 1 system spec con Capybara que recorre las 6 vistas principales y verifica:
- Cada vista tiene `<aside data-testid="admin-sidebar">` (consistency layout).
- Cada tabla tiene clase `admin-table` (consistency table).
- Cada botón destructivo tiene clase `btn-danger`.
- Flash messages aparecen dentro de `[data-flash-container]` y no en otro lado.

**No-objetivo**: visual regression testing (Percy/Chromatic). Fuera de scope.

---

## Decisiones cerradas

| ID | Decisión | Sección impactada |
|---|---|---|
| R1 | Prometheus text format Ruby puro | US1 |
| R2 | Queries on-demand + HTTP cache 5s | US1 |
| R3 | HTTP Basic con ENV vars dedicadas | US1 |
| R4 | Tailwind CDN | US5, US6 |
| R5 | k6 en Compose con perfil load-test | US2 |
| R6 | Brakeman confidence ≥ 2 bloqueante | US3 |
| R7 | bundle-audit sin ignores por defecto | US3 |
| R8 | Worker como servicio Compose | US4 |
| R9 | Sidebar layout con grouping semántico | US6 |
| R10 | Home como ERB estático | US5 |
| R11 | System spec con selectores semánticos | US6 |
