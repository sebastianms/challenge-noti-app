# Tech Stack — Central de Notificaciones

**Estado**: Draft v1 · **Fecha**: 2026-05-10

## 1. Stack base

| Capa | Tecnología | Justificación |
| :---- | :---- | :---- |
| Lenguaje | Ruby 3.4 | Compatible con Rails 8, mejoras de YJIT, sintaxis del enunciado original. |
| Framework | Rails 8.0 | Monolito como mandata el enunciado; trae Hotwire, Solid Queue/Cache nativos, Propshaft. |
| Base de datos | PostgreSQL 17 | Stack existente; `SKIP LOCKED`, JSONB+GIN, range partitioning declarativo. |
| Cola/Broker | **Postgres-as-queue manual** (`SELECT … FOR UPDATE SKIP LOCKED`) | Fiel a la propuesta. Sin infra nueva. Strategy permite migrar a Kafka/SQS sin tocar a los integradores. |
| Cache | `Rails.cache` con `:memory_store` (TTL 5 min) | Reglas y blacklist consultadas en cada envío; in-memory evita hop de red por cada decisión. Trade-off: consistencia eventual ≤ 5 min. |
| Frontend Admin | Hotwire (Turbo + Stimulus) + ERB | Sin SPA; aprovecha back-office existente y SSO actual. |
| Email | Sendgrid HTTP API | Mandato del enunciado. Adapter `EmailChannel` con sandbox para tests. |
| Test | RSpec 3 + FactoryBot + SimpleCov (≥90%) + WebMock (Sendgrid) | Cobertura objetivo 90% por bloque; WebMock para stubbing determinista de llamadas HTTP a Sendgrid. |
| CI | GitHub Actions | Lint (RuboCop, Brakeman) + RSpec + cobertura por PR. |
| Observabilidad | APM (New Relic-compatible) + Sentry + CloudWatch | APM para latencias y throughput; Sentry para errores; CloudWatch para auto-scaling de workers según queue depth. |
| Infra | EC2 ASG (web + worker) + RDS Postgres (master + read replica) | Reutiliza infra existente. |

## 2. Arquitectura — Pipeline de cuatro capas

```text
[25+ equipos] → FooNotification.send(recipient)
       │
       ▼  A. INGESTA (DevEx)
          · construye event
          · idempotency_hash = SHA256(recipient_id + type + context_id + window_ts)
          · INSERT … ON CONFLICT DO NOTHING en notification_events
       │
       ▼  B. DECISIÓN (Motor de reglas)
          · Blacklist? (global / type / channel)  → audit(filtered:blacklisted)
          · Regla?  (rate, cooldown, digest, prio)
              ├─ inmediato → C
              ├─ agrupar  → pending_digests (digest_template)
              └─ filtrar  → audit(filtered:rate_limited|disabled)
       │
       ▼  C. BROKER  dispatch_queue (priority: critical | standard | bulk)
          workers: SELECT … FOR UPDATE SKIP LOCKED LIMIT N
       │
       ▼  D. DESPACHO (Channel Strategy)
          EmailChannel.deliver(event, recipient)
          · maps title→subject, body→html_content
          · X-Correlation-ID header
          · backoff 1m → 5m → 25m → DLQ
       │
       ▼  E. AUDITORÍA transversal
          notification_audit (JSONB + GIN, particionada por día)
          status: received → validated → enqueued → dispatched → delivered|failed|filtered
```

### Retry interno vs. retry externo

Existen **dos mecanismos de reintento distintos** que viven en capas diferentes del pipeline. No deben confundirse al dimensionar la ventana de idempotencia.

| Tipo | Dónde vive | Qué reintenta | Ejemplos | Interactúa con la idempotencia (capa A) |
| :---- | :---- | :---- | :---- | :---- |
| **Retry interno** | Capa D (Worker → Sendgrid) | La llamada HTTP al proveedor cuando falla con 5xx / timeout. Backoff `1 min → 5 min → 25 min → DLQ`. | Sendgrid 503, network blip, throttling 429. | **No.** El evento ya existe en `notification_events` y el job ya está en `dispatch_queue`. Solo se re-llama al adapter del canal. |
| **Retry externo** | Fuera de la plataforma (controller, job del integrador, webhook handler, cron) | La invocación `FooNotification.send(...)`. | Browser retry, ALB retry, Sidekiq retry del controller, webhook re-entregado por Stripe. | **Sí.** Vuelve a pasar por capa A; la `UNIQUE constraint` sobre `idempotency_hash` colapsa la segunda invocación dentro de la ventana. |

**Reintento manual desde DLQ**: la acción "reintentar" en la UI de DLQ **reencola el job existente** con el mismo `correlation_id`. Nunca vuelve a pasar por capa A, por lo que no toca el hash de idempotencia.

**Implicación práctica**: la `idempotency_window` solo debe dimensionarse contra el peor reintentador *externo* del flujo del integrador (HTTP sub-segundo, Sidekiq con backoff de minutos, webhooks con reentregas de horas). El backoff interno del pipeline es independiente.

### Componentes principales (módulos Rails)

```text
app/
├── notifications/                  # API pública para los 25 equipos
│   ├── abstract_notification.rb
│   └── concerns/idempotent.rb
├── central/
│   ├── ingestion/                  # A. Ingesta
│   │   └── event_builder.rb
│   ├── decisioning/                # B. Decisión
│   │   ├── blacklist_evaluator.rb
│   │   ├── rules_engine.rb
│   │   └── decision.rb             # Value object
│   ├── broker/                     # C. Broker
│   │   ├── enqueuer.rb
│   │   ├── worker.rb               # SKIP LOCKED loop
│   │   └── digest_scheduler.rb
│   ├── channels/                   # D. Despacho (Strategy)
│   │   ├── channel_strategy.rb     # interfaz deliver(event, recipient)
│   │   ├── channel_registry.rb
│   │   ├── email_channel.rb
│   │   └── sendgrid_adapter.rb     # mock | real según env
│   └── audit/                      # E. Auditoría
│       ├── audit_logger.rb
│       └── partition_manager.rb    # crea/dropea particiones diarias
├── admin/                          # UI Hotwire (módulo back-office)
│   ├── controllers/
│   ├── views/
│   └── components/
└── webhooks/
    └── sendgrid_bounces_controller.rb
```

## 3. Modelo de datos

### 3.1. Tablas operacionales

| Tabla | Propósito | Notas |
| :---- | :---- | :---- |
| `notification_events` | Eventos ingresados (Capa A). | UNIQUE(`idempotency_hash`); particionada por mes. |
| `notification_rules` | Reglas por tipo (Capa B). | Editable desde UI; cacheada 5 min. |
| `notification_blacklist` | Bloqueos por scope (`global` / `type` / `channel`). | Fuentes: `user_opt_out`, `hard_bounce`, `admin`. |
| `pending_digests` | Items pendientes de agrupación. | Worker `digest_scheduler` los procesa por ventana. |
| `dispatch_queue` | Cola de despacho (Capa C). | Particionada por `priority`; status: `pending|in_flight|done|failed`. |
| `notification_audit` | Log inmutable transversal (Capa E). | JSONB `payload`, JSONB `metadata`, índice GIN; particionada por día. |
| `notification_templates` | Templates por tipo (`title`, `body`, `digest_template`). | Editable desde UI con preview. |

### 3.2. DDL clave (resumen)

```sql
-- Ingesta + idempotencia
CREATE TABLE notification_events (
  id              BIGSERIAL,
  notification_type   TEXT NOT NULL,
  recipient_id    TEXT NOT NULL,
  context_id      TEXT,
  payload         JSONB NOT NULL,
  idempotency_hash TEXT NOT NULL,
  correlation_id  UUID NOT NULL DEFAULT gen_random_uuid(),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (id, created_at),
  UNIQUE (idempotency_hash, created_at)
) PARTITION BY RANGE (created_at);

-- Broker
CREATE TABLE dispatch_queue (
  id              BIGSERIAL PRIMARY KEY,
  event_id        BIGINT NOT NULL,
  priority        TEXT NOT NULL CHECK (priority IN ('critical','standard','bulk')),
  status          TEXT NOT NULL DEFAULT 'pending',
  attempts        INT  NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  locked_at       TIMESTAMPTZ,
  failed_reason   TEXT
);
CREATE INDEX ON dispatch_queue (status, priority, next_attempt_at);

-- Auditoría
CREATE TABLE notification_audit (
  id              BIGSERIAL,
  correlation_id  UUID NOT NULL,
  status          TEXT NOT NULL,
  channel         TEXT,
  rule_snapshot   JSONB,
  payload         JSONB,
  metadata        JSONB,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
CREATE INDEX ON notification_audit USING GIN (payload);
CREATE INDEX ON notification_audit USING GIN (metadata);
CREATE INDEX ON notification_audit (correlation_id);
```

## 4. Contratos públicos (API interna)

### 4.1. API de definición (Parte 1.1)

```ruby
class FooNotification < AbstractNotification
  def self.title(context = {})
    "Título de la notificación"
  end

  def self.body(context = {})
    "Este es el contenido de la notificación"
  end

  # Opcional: template para envíos agrupados
  def self.digest_template(items)
    "Tienes #{items.size} novedades"
  end
end
```

### 4.2. API de envío (Parte 1.2)

```ruby
FooNotification.send(
  "juan_perez@gmail.com",
  context: { comment_id: 42 },          # opcional, alimenta idempotencia
  priority: :standard,                  # :critical | :standard | :bulk
  correlation_id: SecureRandom.uuid     # opcional
)
# => returns Central::Decisioning::Decision (delivered | enqueued | digested | filtered)
```

### 4.3. Channel Strategy

```ruby
module Central::Channels
  class ChannelStrategy
    def deliver(event, recipient) = raise NotImplementedError
    def name                       = raise NotImplementedError
  end
end

Central::Channels::ChannelRegistry.register(:email, EmailChannel.new)
# Para agregar Slack en el futuro:
# Central::Channels::ChannelRegistry.register(:slack, SlackChannel.new)
```

## 5. Decisiones técnicas clave

| ID | Decisión | Alternativa rechazada | Razón |
| :---- | :---- | :---- | :---- |
| ADR-01 | Postgres como cola (manual SKIP LOCKED) | Solid Queue (Rails 8) / Sidekiq+Redis | Mantenemos exactamente lo de la propuesta; Strategy permite migrar después. |
| ADR-02 | Idempotencia con SHA256 + UNIQUE | Lock de aplicación / Redis SETNX | ACID gratis; un solo lugar de verdad; sin nueva infra. |
| ADR-03 | Reglas cacheadas en `:memory_store` 5 min | Consultar Postgres en cada decisión | Latencia p95 < 50 ms. Trade-off: consistencia eventual aceptada y documentada. |
| ADR-04 | Auditoría con JSONB + GIN, particionada por día | Tabla plana con DELETE masivos | DROP TABLE diario es metadata-only, sin Vacuum. |
| ADR-05 | Hotwire para UI Admin | SPA React + API JSON | Sin frontend nuevo; aprovecha back-office y SSO existente. |
| ADR-06 | Channel Strategy con Registry | `if channel == :email`, switch | Agregar SMS/Slack/Push no toca las 25+ notificaciones existentes. |
| ADR-07 | Sendgrid Adapter con sandbox | Llamar a Sendgrid real en tests | No gastar cuota; tests deterministas con VCR. |

## 6. Observabilidad

| Métrica | Origen | Alarma |
| :---- | :---- | :---- |
| `queue_depth` por prioridad | `dispatch_queue` count | > 10k en `standard` durante > 5 min |
| `dlq_size` | `dispatch_queue` con `status=failed` | crecimiento > 100/min |
| `sendgrid_5xx_rate` | adapter | > 1% en 5 min |
| `sendgrid_429_rate` | adapter | > 0.5% en 5 min |
| Latencia ingesta p95 | APM | > 50 ms |
| `bounce_rate` | webhook | > 5% |

## 7. Seguridad

- **Autenticación UI**: SSO del monolito (reutilizado). Roles `admin`, `product`, `support`, `engineering`.
- **Webhook Sendgrid**: validación de firma HMAC antes de aceptar el evento.
- **PII en auditoría**: `payload` y `metadata` se persisten cifrados a nivel disco (RDS encryption-at-rest); en logs aplicativos los emails se enmascaran (`j***@gmail.com`).
- **Idempotency hash** no incluye PII en claro: el hash es estable pero one-way.

## 8. Limitaciones reconocidas

- Postgres como cola tiene techo cómodo ~500-1000 rps; la migración a Kafka/SQS está prevista en el roadmap evolutivo.
- Consistencia eventual de reglas hasta 5 min entre nodos (TTL del cache).
- Sin rate limiter proactivo coordinado contra Sendgrid (R-06 en riesgos): la cola actúa como buffer pero no controla throughput de salida.
- Acoplamiento al monolito mitigado con feature flags por equipo.
