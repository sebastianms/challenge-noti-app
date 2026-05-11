# Implementation Plan — 005-blacklist-bounces

**Branch**: `005-blacklist-bounces` (en main) · **Date**: 2026-05-11

## Summary

Implementar opt-out duro vía `notification_blacklist` con tres dimensiones (global / type / channel), `BlacklistEvaluator` pre-reglas, e integración del webhook existente (feature 003) para auto-blacklistear hard bounces / dropped / spamreport. UI `/admin/blacklist` con listado, alta y remoción auditada.

## Technical Context

| Aspecto | Decisión |
|---------|----------|
| Language/Version | Ruby 3.3 |
| Framework | Rails 8.1 |
| Storage | PostgreSQL 17 (NULLS NOT DISTINCT — feature de PG 15+) |
| Testing | RSpec + FactoryBot + WebMock |
| Project Type | Monolito Rails (módulo dentro de `app/central`) |
| Dependencias nuevas | ninguna |

## Constitution Check

- ✅ `mission.md` § 5: blacklist (global/type/channel) con tres fuentes (manual, hard bounce webhook, admin UI) está dentro del scope MVP.
- ✅ `tech-stack.md`: PostgreSQL como única persistencia, sin servicios externos nuevos.
- ✅ `roadmap.md` Phase 6: alineado con DoD ("destinatario en blacklist nunca recibe envíos del scope bloqueado; auditado con motivo blacklisted; un hard bounce de Sendgrid se refleja en blacklist en < 30 s").
- ✅ Reutiliza componentes existentes: `RecipientNormalizer` (feature 001), `WebhookEventWorker` (feature 003), `NotificationAudit` particionado (feature 003), HTTP Basic auth (feature 003).

Sin violaciones que documentar en Complexity Tracking.

## Project Structure

```
app/
  central/
    decisioning/
      blacklist_evaluator.rb         # NEW
      notification_blacklist.rb      # NEW (AR model)
    broker/
      webhook_event_worker.rb        # EXTEND (rama hard_failure?)
    ingestion/
      event_builder.rb               # EXTEND (call BlacklistEvaluator pre-rules)
  controllers/
    admin/
      blacklist_controller.rb        # NEW (index, create, destroy)
  views/
    admin/
      blacklist/
        index.html.erb               # NEW
        _row.html.erb                # NEW
        _form.html.erb               # NEW

db/
  migrate/
    20260513000001_create_notification_blacklist.rb  # NEW

spec/
  central/
    decisioning/
      blacklist_evaluator_spec.rb
      notification_blacklist_spec.rb     # schema + validations
    broker/
      webhook_event_worker_blacklist_spec.rb
  integration/
    blacklist_pipeline_spec.rb           # US1, US2, US3 end-to-end
  requests/
    admin/
      blacklist_spec.rb                  # HTTP contracts
  support/
    factories/
      notification_blacklists.rb

.design-logs/
  ADL-010-blacklist-pre-rules-evaluation.md     # NEW
```

## Phase 0 — Research

Completado en `research.md`. 7 decisiones (R1-R7) sin unknowns pendientes.

## Phase 1 — Design

| Artifact | Contenido |
|----------|-----------|
| `data-model.md` | Tabla `notification_blacklist` + índices + CHECKs. Reutilización de `notification_audit`. |
| `contracts/blacklist_evaluator.md` | Interfaz Ruby + integración con `EventBuilder`. |
| `contracts/admin_blacklist_http.md` | GET/POST/DELETE `/admin/blacklist` + auth + responses. |
| `contracts/webhook_blacklist_integration.md` | Tabla decisional event → audit/blacklist + transaccionalidad. |
| `quickstart.md` | 5 escenarios manuales + smoke benchmark de SC-005. |

## Phase 2 — Implementation Slices

Orden alineado con user stories (Phase 5 del SDD: Implement).

### Setup
- Migration `notification_blacklist` con CHECKs, UNIQUE NULLS NOT DISTINCT, 3 índices.
- Modelo AR `Central::Decisioning::NotificationBlacklist` con validaciones.
- Factory + spec de schema.

### Foundational
- `BlacklistEvaluator` con query única OR + LIMIT 1.
- `EventBuilder` invoca `BlacklistEvaluator` antes de `RulesEngine`.
- Audit `filtered` con `reason=blacklisted` cuando matchea.

### US1 — Opt-out manual (P1)
- `NotificationBlacklist.create!` desde consola funcional.
- Tests: scope global filtra todo, scope type solo ese tipo, scope channel solo ese canal, casing distinto.
- Integration spec: `FooNotification.send` con blacklist activa → `:filtered`, queue vacía.

### US2 — Auto-blacklist desde webhook (P1)
- Extender `WebhookEventWorker#process_event`: rama `hard_failure?(event)` → insert blacklist en misma transacción que audit.
- Tests: bounce/bounce → blacklist; bounce/blocked → no; dropped → sí; spamreport → sí; deferred → no; idempotente.
- Integration spec: POST webhook firmado → process_batch → blacklist + audit.

### US3 — UI admin (P2)
- `Admin::BlacklistController` con index/create/destroy.
- Vistas Hotwire (reusar layout de `/admin/audits`).
- Tests de request: 401 sin auth, 200 con auth, 302 tras POST, audit `blacklist_removed` tras DELETE.

### Polish
- ADL-010: rationale de evaluación pre-reglas + transaccionalidad webhook.
- README: sección "Blacklist y opt-outs" con ejemplos consola + UI.
- Roadmap: marcar Phase 6 `[DONE]` con resumen.
- Smoke run completo (rubocop + rspec + brakeman + bundler-audit).

## Complexity Tracking

Sin violaciones. La decisión "auditar removals reutilizando `notification_audit` con `notification_type` sintético" se justifica en R5 de research.md (evita schema nuevo para caso de uso de baja frecuencia).

## Riesgos y Mitigaciones

| Riesgo | Mitigación |
|--------|------------|
| `NULLS NOT DISTINCT` requiere PG 15+ | Stack ya en PG 17 (tech-stack.md). Sin riesgo. |
| Race: evento entra antes de que webhook procese hard bounce previo | Aceptado en spec (edge cases). El siguiente envío sí queda bloqueado. SLO de 30 s lo acota. |
| Migración inserta duplicados al re-correr | UNIQUE constraint + ON CONFLICT en INSERTs garantizan idempotencia. |
| BlacklistEvaluator agrega ≥ 5 ms al p95 | Índice `(recipient_canonical, scope)` + LIMIT 1. Benchmark en quickstart valida SC-005. |
