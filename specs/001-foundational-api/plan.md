# Implementation Plan: Foundational Notification API & Idempotencia

**Feature Branch**: `001-foundational-api` · **Date**: 2026-05-10

## Summary

Implementar la capa de cimientos de la Central de Notificaciones: el contrato público `AbstractNotification` que los 25+ equipos extenderán, y el `EventBuilder` que captura eventos con idempotencia determinista vía hash SHA256 + tumbling window de 1 min + `UNIQUE` constraint en Postgres con `ON CONFLICT DO NOTHING`. No envía correos: solo deduplica y persiste eventos con `correlation_id` trazable.

## Technical Context

| Aspecto | Valor |
| :---- | :---- |
| Lenguaje | Ruby 3.4 |
| Framework | Rails 8.0 (módulo dentro del monolito) |
| Storage | PostgreSQL 16 (master + read replica existentes) |
| Testing | RSpec 6 + FactoryBot + SimpleCov (≥90%) + DatabaseCleaner |
| Concurrencia (tests) | `parallel_tests` para validar idempotencia bajo carga real |
| Observabilidad | Logs estructurados (JSON) con `correlation_id`; APM hooks `Central::Ingestion::EventBuilder#build` |
| Tipo de proyecto | Módulo dentro del monolito Rails (no servicio separado) |

## Constitution Check

| Gate | Estado | Evidencia |
| :---- | :---- | :---- |
| Alineado con `mission.md` | ✅ | Cubre R1 y R4 declarados como MVP. Sin contradicciones de alcance. |
| Alineado con `tech-stack.md` | ✅ | Usa Postgres, Rails 8, módulo en monolito, sin infra nueva. ADR-02 (idempotencia con SHA256+UNIQUE) directamente implementado aquí. |
| Alineado con `roadmap.md` | ✅ | Es exactamente la Phase 2 (Foundational). Bloquea las siguientes fases por diseño. |
| User stories independientemente testeables | ✅ | US1, US2, US3 validables sin envío real ni infraestructura externa. |
| Sin violaciones del principio "1 archivo, 1 línea" para integradores | ✅ | El integrador solo crea una clase con `title` y `body`; nada más. |

**Resultado**: Constitution Check PASS. Sin violaciones que justifiquen `Complexity Tracking`.

## Project Structure

```text
challenge-noti-app/
├── Gemfile
├── config/
│   ├── application.rb
│   ├── database.yml
│   └── routes.rb
├── db/
│   └── migrate/
│       └── 20260510000001_create_notification_events.rb
├── app/
│   ├── notifications/
│   │   └── abstract_notification.rb        # Contrato público (R1)
│   └── central/
│       ├── ingestion/
│       │   ├── event_builder.rb            # Calcula hash, persiste, retorna SendResult
│       │   ├── recipient_normalizer.rb     # email vs user_id, lowercase + trim
│       │   ├── idempotency_hash.rb         # SHA256 determinista
│       │   └── send_result.rb              # Value object: :created | :duplicate | :rejected
│       └── models/
│           └── notification_event.rb       # ActiveRecord
├── spec/
│   ├── rails_helper.rb
│   ├── spec_helper.rb
│   ├── support/
│   │   └── concurrency_helper.rb           # Hilos paralelos para tests de idempotencia
│   ├── notifications/
│   │   └── abstract_notification_spec.rb
│   └── central/
│       └── ingestion/
│           ├── event_builder_spec.rb
│           ├── recipient_normalizer_spec.rb
│           ├── idempotency_hash_spec.rb
│           └── send_result_spec.rb
├── .github/
│   └── workflows/
│       └── ci.yml                          # RSpec + RuboCop + Brakeman + cobertura
├── .rubocop.yml
└── README.md
```

## Phase 0 — Research

Ver [research.md](research.md) para decisiones técnicas detalladas. Resumen:

- **R-01**: Postgres `UNIQUE` + `ON CONFLICT DO NOTHING` vs. lock aplicativo → escogido por atomicidad gratuita.
- **R-02**: SHA256 vs. MD5 vs. xxHash → SHA256 (estándar, librería estándar Ruby, costo despreciable a 140 rps).
- **R-03**: Particionamiento de `notification_events` desde el día 1 → sí, mensual por `created_at`, evita downtime de migración futura.
- **R-04**: `correlation_id` con UUIDv4 vs. UUIDv7 → UUIDv4 (no necesitamos ordenamiento temporal en este nivel).
- **R-05**: Detección email vs user_id → heurística `recipient.include?("@")` documentada como decisión consciente.

## Phase 1 — Design

### Entities & contracts

- [data-model.md](data-model.md): tabla `notification_events`, campos, índices, particionamiento.
- [contracts/abstract_notification.rb](contracts/abstract_notification.rb): API pública para integradores.
- [contracts/send_result.rb](contracts/send_result.rb): contrato del valor de retorno.
- [contracts/event_builder.rb](contracts/event_builder.rb): contrato del builder interno.
- [quickstart.md](quickstart.md): escenarios de validación end-to-end.

### Key flows

```text
Integrador
  │
  │  FooNotification.send("juan@x.com", context: { invoice: 42 })
  ▼
AbstractNotification.send (delega)
  │
  ▼
Central::Ingestion::EventBuilder.build
  │
  ├─► RecipientNormalizer.normalize("juan@x.com")
  │     → { type: :email, canonical: "juan@x.com" }
  │
  ├─► IdempotencyHash.compute(
  │     notification_type: "foo",
  │     recipient_canonical: "juan@x.com",
  │     context_id: "42",
  │     window_ts: floor(now_utc, 1.min)
  │   )
  │
  └─► NotificationEvent.insert_on_conflict_do_nothing(...)
         │
         ├─ inserted=true  → SendResult.created(correlation_id: <new uuid>)
         └─ inserted=false → SendResult.duplicate(correlation_id: <existing>)
```

## Complexity Tracking

| Violación | Por qué se necesita | Alternativa más simple rechazada |
| :---- | :---- | :---- |
| (ninguna) | — | — |

No hay violaciones de la constitución ni desviaciones de simplicidad. Cero entradas.

## Out of scope (esta feature)

- Envío real de email (es la siguiente feature, `002-email-dispatch`).
- Decisión por reglas o blacklist (feature `003-rules-engine`, `005-blacklist`).
- Auditoría con transiciones de estado (feature `004-audit`). Esta feature solo persiste el evento inicial; las transiciones `validated → enqueued → dispatched` no aplican aún.
- UI Admin (features `007`, `008`, `009`).
