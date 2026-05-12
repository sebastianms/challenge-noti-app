# Contract — GET /metrics

## Endpoint

```
GET /metrics
```

## Auth

HTTP Basic Auth. Credenciales en ENV:
- `METRICS_BASIC_AUTH_USER`
- `METRICS_BASIC_AUTH_PASSWORD`

Si las ENV no están definidas, el endpoint responde **503 Service Unavailable** (no se expone sin auth configurada — failsafe).

## Response

### 200 OK

```
Content-Type: text/plain; version=0.0.4; charset=utf-8
Cache-Control: public, max-age=5
```

Body (Prometheus text exposition format):

```
# HELP notif_queue_depth Jobs pendientes de envío en dispatch_queue.
# TYPE notif_queue_depth gauge
notif_queue_depth 42

# HELP notif_dlq_size Jobs en estado failed (DLQ).
# TYPE notif_dlq_size gauge
notif_dlq_size 7

# HELP notif_events_ingested_total Eventos ingestados en las últimas 24h (proxy de counter).
# TYPE notif_events_ingested_total gauge
notif_events_ingested_total 18432

# HELP notif_dispatch_errors_total Jobs en DLQ agrupados por clase de error.
# TYPE notif_dispatch_errors_total gauge
notif_dispatch_errors_total{class="TransientError"} 4
notif_dispatch_errors_total{class="PermanentError"} 2
notif_dispatch_errors_total{class="Unknown"} 1

# HELP notif_bounce_rate_5m Tasa de bounces sobre total de envíos en últimos 5min.
# TYPE notif_bounce_rate_5m gauge
notif_bounce_rate_5m 0.012

# HELP notif_webhook_lag_seconds Edad en segundos del webhook_event más antiguo pendiente.
# TYPE notif_webhook_lag_seconds gauge
notif_webhook_lag_seconds 3.5
```

### 401 Unauthorized

Body vacío. Header `WWW-Authenticate: Basic realm="Metrics"`.

### 503 Service Unavailable

Cuando:
- ENV de auth no configuradas
- Base de datos no responde

Body mínimo: `# metrics unavailable\n`. No expone stack trace.

## Performance budget

- p95 de respuesta < 100 ms con suite de datos realistas (10k jobs en queue).
- Scrape interval recomendado: ≥ 15 s (documentado en runbook).

## Tests requeridos

- 200 con todas las métricas presentes y formato válido.
- 401 sin auth.
- 503 con DB caída (simulable bajando `db` en Compose).
- HTTP cache header presente.
- Performance: response < 100 ms con 10k filas en dispatch_queue.
