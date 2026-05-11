# Implementation Plan: 003-audit-query

**Branch**: `003-audit-query` | **Date**: 2026-05-11
**Spec**: [spec.md](spec.md) · **Data Model**: [data-model.md](data-model.md) · **Research**: [research.md](research.md)

## Summary

Capa de consulta y operación sobre `notification_audit`: agentes de soporte buscan timelines por `correlation_id` o por filtros combinados (destinatario, status, fechas) con paginación; eventos de SendGrid llegan vía webhook firmado HMAC, se persisten async en `webhook_events` y un `WebhookEventWorker` los proyecta en `notification_audit` con `source = sendgrid_webhook`; un `PartitionManager` crea la partición mensual siguiente y elimina las antiguas (con guardrail de 3 meses de protección).

## Technical Context

**Language/Version**: Ruby 3.3
**Primary Dependencies**: Rails 8.1, PostgreSQL 17 (partitioning declarativo), Hotwire (Turbo + Stimulus), WebMock (tests)
**Storage**: PostgreSQL (tablas existentes + 1 nueva `webhook_events`, 2 columnas nuevas en `notification_audit`)
**Testing**: RSpec 3 + FactoryBot + SimpleCov (≥90%)
**Target Platform**: Linux server (mismo runtime que features 001/002)
**Project Type**: Web service (controllers + workers + ERB views)

## Constitution Check

| Gate | Resultado |
|---|---|
| `mission.md` SC: soporte responde "¿por qué Juan no recibió X?" en segundos | ✅ US1 + US2 lo entregan directamente |
| `tech-stack.md` ADR-04: auditoría JSONB + GIN particionada | ✅ Extendemos sin cambiar el patrón |
| `tech-stack.md` ADR-05: Hotwire para Admin UI | ✅ Endpoint Hotwire con Turbo Frames |
| `tech-stack.md` Sección Componentes: `webhooks/sendgrid_bounces_controller.rb` previsto | ✅ Lo materializamos (renombrado a `sendgrid_events_controller`) |
| Strategy/Registry para canales | ✅ No tocamos canales, solo lectura |
| Idempotencia y append-only | ✅ Audit sigue siendo append-only; webhook_events tiene status, no semántica de idempotencia |

Sin violaciones. Sin justificaciones requeridas.

## Project Structure

```text
app/
├── central/
│   ├── audit/
│   │   ├── notification_audit.rb              # (extender: source, recipient_canonical)
│   │   ├── partition_manager.rb               # NUEVO — create_next / drop_old / safety guardrail
│   │   └── audit_search.rb                    # NUEVO — query object (correlation_id | filtros)
│   ├── broker/
│   │   ├── enqueuer.rb                        # (extender: setear recipient_canonical + source=internal)
│   │   ├── worker.rb                          # (extender: setear recipient_canonical + source=internal)
│   │   └── webhook_event_worker.rb            # NUEVO — SKIP LOCKED sobre webhook_events
│   └── webhooks/                              # NUEVO submódulo
│       ├── webhook_event.rb                   # AR model
│       ├── sendgrid_signature.rb              # HMAC validation (ED25519 per SendGrid v3)
│       └── sendgrid_event_processor.rb        # raw payload → entries de notification_audit
├── controllers/
│   ├── webhooks/
│   │   └── sendgrid_events_controller.rb      # POST /webhooks/sendgrid
│   └── admin/
│       └── audits_controller.rb               # GET /admin/audits (HTTP Basic)
└── views/admin/audits/
    ├── index.html.erb                         # form + table + turbo_frame pagination
    └── _row.html.erb                          # parcial reusable
lib/tasks/
└── partitions.rake                            # partitions:rotate
db/migrate/
├── 20260511000001_extend_notification_audit_with_source_and_recipient.rb
└── 20260511000002_create_webhook_events.rb
spec/
├── central/audit/
│   ├── partition_manager_spec.rb
│   └── audit_search_spec.rb
├── central/broker/
│   └── webhook_event_worker_spec.rb
├── central/webhooks/
│   ├── sendgrid_signature_spec.rb
│   └── sendgrid_event_processor_spec.rb
├── controllers/
│   ├── webhooks/sendgrid_events_controller_spec.rb
│   └── admin/audits_controller_spec.rb
├── integration/
│   ├── webhook_ingest_spec.rb
│   └── audit_search_spec.rb
└── db/
    └── webhook_events_schema_spec.rb
```

## Estructura de rutas (Rails)

```ruby
# config/routes.rb
namespace :webhooks do
  post "sendgrid", to: "sendgrid_events#create"
end

namespace :admin do
  resources :audits, only: [:index]
end
```

## Complexity Tracking

> Sin violaciones de constitución. Justificación de las 2 decisiones que ameritan ADL:
>
> - **ADL-007 (planeada)**: SKIP LOCKED reusado para `webhook_events`. La decisión ya existe en ADL-005; basta con extender ese ADL con nota de extensión.
> - **ADL-008 (planeada)**: HMAC validation con Ed25519 (SendGrid Event Webhook v3 usa Ed25519, no HMAC-SHA256). Decisión nueva, requiere ADL.

## Open Questions (resolved in research.md)

- HMAC vs Ed25519 para SendGrid webhooks → resuelto en research.md
- Backfill de `recipient_canonical` en audits existentes → no backfill (datos de dev), nueva columna NULLable
- Headers de SendGrid para signature verification → resuelto en research.md
