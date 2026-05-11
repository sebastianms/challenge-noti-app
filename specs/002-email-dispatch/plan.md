# Implementation Plan — 002-email-dispatch

**Branch**: `002-email-dispatch` | **Fecha**: 2026-05-10

---

## Summary

Implementar la Capa C (Broker) y Capa D (Channel Strategy + EmailChannel) del pipeline de notificaciones. Al terminar, `FooNotification.send("a@b.com")` produce un correo verificable vía sandbox de Sendgrid (WebMock), con reintentos automáticos y DLQ tras 3 fallos.

---

## Technical Context

| Ítem | Valor |
|------|-------|
| Lenguaje | Ruby 3.3 |
| Framework | Rails 8.1 |
| Base de datos | PostgreSQL 17 |
| Testing | RSpec + WebMock (agregar) + FactoryBot |
| HTTP client | `Net::HTTP` nativo o `Faraday` (evaluar en implementación) |
| Cobertura objetivo | ≥ 90% en módulos nuevos |

---

## Constitution Check

| Constraint | Estado |
|------------|--------|
| Stack Rails 8.1 + Postgres 17 | ✅ Respetado |
| Broker con `SKIP LOCKED` (ADR-01) | ✅ Implementado en Worker |
| Channel Strategy intercambiable (ADR-06) | ✅ `ChannelRegistry` + `ChannelStrategy` interface |
| Sendgrid con sandbox (ADR-07) | ✅ WebMock stubs en tests |
| Sin infra nueva | ✅ Solo tablas Postgres |
| Cobertura ≥ 90% | ✅ Objetivo por bloque |
| Enqueue en misma transacción (Clarify A) | ✅ Dentro de `EventBuilder` |

---

## Project Structure (nueva en esta fase)

```
app/
├── central/
│   ├── broker/
│   │   ├── dispatch_queue.rb          # AR model (tabla dispatch_queue)
│   │   ├── enqueuer.rb                # Crea job en dispatch_queue
│   │   └── worker.rb                  # SKIP LOCKED loop + backoff
│   ├── channels/
│   │   ├── channel_strategy.rb        # Interfaz abstracta
│   │   ├── channel_registry.rb        # Registry de canales activos
│   │   ├── email_channel.rb           # Implementación email
│   │   └── sendgrid_adapter.rb        # HTTP client hacia Sendgrid v3
│   └── audit/
│       └── notification_audit.rb      # AR model (tabla notification_audit)

db/migrate/
├── 20260510000002_create_dispatch_queue.rb
└── 20260510000003_create_notification_audit.rb

spec/
├── factories/
│   ├── dispatch_queues.rb
│   └── notification_audits.rb
├── central/
│   ├── broker/
│   │   ├── dispatch_queue_spec.rb     # backoff, estado, permanent_failure?
│   │   ├── enqueuer_spec.rb           # crea job, no crea en duplicate
│   │   └── worker_spec.rb             # SKIP LOCKED, backoff, DLQ
│   └── channels/
│       ├── channel_registry_spec.rb   # register, for, unknow channel
│       ├── email_channel_spec.rb      # deliver, mapeo title/body, no_email
│       └── sendgrid_adapter_spec.rb   # stub WebMock, headers, 202/5xx/4xx
└── integration/
    └── email_dispatch_spec.rb         # happy path + DLQ end-to-end
```

---

## Decisiones de implementación

### HTTP client para Sendgrid
Usar `Net::HTTP` nativo para evitar nueva dependencia (Faraday añade ~20 gemas transitivas). El adapter es un objeto pequeño con un solo endpoint; `Net::HTTP` es suficiente.

### `EventBuilder` y el enqueue
`EventBuilder#persist` (método privado existente) se extiende para, tras el INSERT exitoso, llamar a `Central::Broker::Enqueuer.enqueue(event)` dentro del mismo bloque `transaction`. Si la inserción devuelve cero filas (duplicado), no se llama al enqueuer.

### Worker — dos interfaces
- `Worker#start(batch_size: 10, sleep_interval: 5)` — loop continuo para producción (rake task).
- `Worker#process_batch(batch_size: N)` — un solo ciclo sin sleep para tests.

### `notification_audit` — escritura directa
En Phase 3, el `EmailChannel` y el `Enqueuer` escriben en `notification_audit` directamente (sin `AuditLogger`). Phase 4 extrae esta lógica a `Central::Audit::AuditLogger` y añade búsqueda.

### Backoff schedule
```ruby
BACKOFF = [1.minute, 5.minutes, 25.minutes].freeze
# attempts=0 → primer intento inmediato
# attempts=1 → próximo en NOW() + 1.minute
# attempts=2 → próximo en NOW() + 5.minutes
# attempts=3 → DLQ (permanent_failure?)
```

### Clasificación de errores HTTP
- `202` → `:delivered`
- `4xx` (excepto `429`) → error permanente → DLQ inmediato (no incrementa backoff schedule)
- `429` + `5xx` + timeout → error transitorio → backoff normal

---

## ADL a crear

- **ADL-003**: Broker con `dispatch_queue` en Postgres + `SKIP LOCKED` (documenta ADR-01 implementado)
- **ADL-004**: WebMock como mecanismo de test para HTTP externo (decisión tomada en Clarify)

---

## Gemas a agregar

```ruby
# Gemfile — grupo :test
gem "webmock", "~> 3.0"
```

`webmock` requiere configuración en `spec/support/webmock.rb`:
```ruby
require "webmock/rspec"
WebMock.disable_net_connect!(allow_localhost: true)
```
