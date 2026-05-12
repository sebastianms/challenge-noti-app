# Data Model — 009-observability-perf-hardening

**Fecha**: 2026-05-12

## Tablas nuevas

**Ninguna.** Esta feature no introduce schema changes. Toda la información operativa se deriva de tablas existentes.

## Tablas leídas (sin modificar)

| Tabla | Para qué | Métrica / vista |
|---|---|---|
| `dispatch_queue` | `queue_depth` (status='pending'), `dlq_size` (status='failed'), `dispatch_errors_total` (group by failed_reason) | `/metrics` |
| `notification_audit` | `bounce_rate_5m` (status='failed' / total en 5m), error rate por type | `/metrics`, dashboards |
| `notification_events` | `events_ingested_total` (proxy 24h) | `/metrics` |
| `webhook_events` | `webhook_lag_seconds` (max age de pending) | `/metrics` |
| `admin_users` | rol del usuario actual para sidebar role-aware | layout admin |
| `notification_rules`, `notification_blacklist`, `notification_templates` | conteos en home/dashboard si se incluyen como insights | landing (US5) — opcional |

## Métricas — esquema lógico

| Métrica | Tipo Prometheus | Labels | Source query |
|---|---|---|---|
| `notif_queue_depth` | gauge | — | `COUNT(*) FROM dispatch_queue WHERE status='pending'` |
| `notif_dlq_size` | gauge | — | `COUNT(*) FROM dispatch_queue WHERE status='failed'` |
| `notif_events_ingested_total` | gauge (proxy de counter) | — | `COUNT(*) FROM notification_events WHERE created_at > NOW() - INTERVAL '24h'` |
| `notif_dispatch_errors_total` | gauge (proxy) | `class` | `GROUP BY split_part(failed_reason,':',1)` |
| `notif_bounce_rate_5m` | gauge | — | failed/total ratio en 5min de `notification_audit` |
| `notif_webhook_lag_seconds` | gauge | — | `EXTRACT(EPOCH FROM NOW() - MIN(created_at))` en webhook_events pending |

**Prefijo**: `notif_` para evitar colisiones futuras con métricas de Rails (`puma_*`, `rack_*`).

## Reporte de load test — esquema lógico (no persiste en DB)

Archivo markdown auto-generado en `specs/009-.../reports/load-test-YYYYMMDD-HHMM.md`:

| Campo | Tipo | Origen (k6 JSON) |
|---|---|---|
| `target_rps` | int | invocación del scenario |
| `duration_s` | int | invocación |
| `total_requests` | int | `metrics.iterations.count` |
| `p50_ms` | float | `metrics.http_req_duration.values["p(50)"]` |
| `p95_ms` | float | `metrics.http_req_duration.values["p(95)"]` |
| `p99_ms` | float | `metrics.http_req_duration.values["p(99)"]` |
| `error_rate` | float | `metrics.http_req_failed.values.rate` |
| `queue_depth_max` | int | sample tomado durante el run via `/metrics` (snapshot externo) |
| `verdict` | enum | PASS si `p95 < 200ms` y `error_rate < 0.005`, FAIL si no |

Sin persistencia en DB. El archivo se commitea bajo `specs/009-.../reports/`.

## Cambios en migrations

**Ninguno.** Si el roadmap evoluciona y `events_ingested_total` debe ser counter real (cumulative monotonic), se introducirá una tabla `metric_counters` en una feature futura, fuera de este scope.
