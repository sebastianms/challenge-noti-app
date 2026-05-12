# ADL-015 — Endpoint /metrics: Prometheus text exposition, auth runtime, HTTP cache

**Fecha**: 2026-05-12
**Estado**: Aceptado

## Contexto

Se necesita exponer métricas operacionales (profundidad de cola, DLQ, tasa de bounce, etc.) para integración con Prometheus/Grafana sin agregar dependencias externas.

## Decisiones

### 1. Formato Prometheus text exposition generado a mano

Se implementó `Observability::PrometheusFormatter` que genera el formato `text/plain; version=0.0.4` directamente en Ruby, sin la gema `prometheus_exporter` ni `prometheus-client`.

**Razón**: El conjunto de métricas es estático y pequeño (6 gauges). Una gema agrega ~500KB de dependencias, un proceso de push externo y complejidad de threading para un payload que cabe en < 1KB. El formato es suficientemente simple para mantenerse a mano.

### 2. Queries on-demand en cada scrape

`Observability::MetricsCollector` ejecuta 6 queries SQL en cada request. No hay caché en Ruby — se delega al HTTP cache header `Cache-Control: public, max-age=5`.

**Razón**: Con scrape interval recomendado ≥ 15s y p95 < 100ms verificado con 10k filas, el costo es aceptable. Caché en memoria agregaría estado mutable al proceso y complicaría el modelo de despliegue multi-worker.

### 3. Auth HTTP Basic con verificación en runtime

Se usa `authenticate_or_request_with_http_basic` en un `before_action` en lugar de `http_basic_authenticate_with` a nivel de clase.

**Razón**: `http_basic_authenticate_with` evalúa las credenciales en tiempo de carga de clase (constantes congeladas en boot). Esto impide el stubbing en tests (`stub_const` no afecta valores ya capturados en el método de clase). El `before_action` lee `MetricsAuth::USER/PASSWORD` en cada request, manteniendo la seguridad y habilitando tests deterministas.

### 4. Failsafe 503 cuando las ENV no están configuradas

Si `MetricsAuth::CREDENTIALS_PRESENT` es `false` (ENV vacías en boot), el endpoint responde 503 en lugar de exponer métricas sin auth.

**Razón**: Previene exposición accidental en entornos donde las variables de entorno no se configuraron. Es un opt-in explícito: las métricas solo se exponen cuando el operador provee credenciales.

## Consecuencias

- Sin dependencias nuevas en el Gemfile.
- El formato text exposition es compatible con Prometheus ≥ 2.x (version=0.0.4).
- Scrape interval mínimo recomendado en runbook: 15s (documentado en T031).
- Si en el futuro se agregan métricas de histograma o counters persistentes, se deberá migrar a `prometheus-client` con proceso de push o pull dedicado.
