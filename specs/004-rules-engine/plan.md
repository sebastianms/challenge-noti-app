# Implementation Plan: Motor de reglas + digest + cache

**Branch**: `004-rules-engine` | **Date**: 2026-05-11

## Summary

Insertar una capa de **decisión** entre Ingesta (capa A) y Broker (capa C). El `EventBuilder` deja de invocar a `Enqueuer.enqueue` directamente; ahora delega a `Decisioning::RulesEngine`, que consulta `notification_rules` (cacheada en `Rails.cache`, TTL 5 min), evalúa rate limit / cooldown / digest / canales y retorna un `Decision` value object. Según el tipo de decisión:

- `:dispatch` → flujo actual (`Enqueuer.enqueue`).
- `:digest` → INSERT en `pending_digests` con `dispatch_at = now + window`.
- `:filter` → solo audit con `reason`.

Un nuevo worker `DigestScheduler` consume `pending_digests WHERE dispatch_at <= now` con `FOR UPDATE SKIP LOCKED`, agrupa por `(notification_type, recipient_canonical)`, crea 1 fila en `dispatch_queue` con payload fusionado y marca los originales `consolidated`.

## Technical Context

- **Language/Version**: Ruby 3.3 / Rails 8.1
- **Primary Dependencies**: ActiveRecord, Rails.cache (default `:memory_store` en dev/test, configurable a Memcached/Redis en prod)
- **Storage**: PostgreSQL 17 — tablas `notification_rules`, `pending_digests`; queries sobre `notification_audit` (rate limit count)
- **Testing**: RSpec + DatabaseCleaner; activación de cache real en algunos specs vía `Rails.cache = ActiveSupport::Cache::MemoryStore.new`
- **Target Platform**: Linux server / Docker
- **Project Type**: Rails monolith (capa interna `app/central/decisioning/`)

## Constitution Check

| Requisito | Cumplimiento |
|---|---|
| Stack alineado con `tech-stack.md` | ✅ Rails 8.1, PG 17, Rails.cache; estructura ya prevista en `app/central/decisioning/` |
| `mission.md` R5 (motor de reglas + cache) | ✅ Cierra el loop "configurar sin redeploy" |
| ADL-003 (sin FK en particionadas) | ✅ `pending_digests` no es particionada → puede usar FKs si se quisiera, pero referencia `correlation_id` por valor |
| Hotwire para UI Admin (ADR-05) | N/A — UI se difiere a Phase 7. Esta feature solo expone CRUD vía consola Rails |
| Pipeline asincrónico (rake task) | ✅ `DigestScheduler` corre como rake task con SKIP LOCKED, igual que Worker / WebhookEventWorker |

Sin violaciones.

## Project Structure

```
app/central/
├── decisioning/                    # NUEVO — capa B del pipeline
│   ├── notification_rule.rb        # AR model
│   ├── rule_cache.rb               # wrapper sobre Rails.cache (TTL 5 min, invalidación)
│   ├── rules_engine.rb             # entrypoint: .decide(event) → Decision
│   ├── rate_limit_evaluator.rb     # cuenta envíos en notification_audit
│   └── decision.rb                 # value object (:dispatch | :digest | :filter)
├── broker/
│   ├── digests/                    # subcarpeta NUEVA dentro de broker existente
│   │   └── pending_digest.rb       # AR model
│   ├── digest_scheduler.rb         # NUEVO — worker con SKIP LOCKED + consolidación
│   └── enqueuer.rb                 # EXTENDIDO — acepta payload custom (digest)
└── ingestion/
    └── event_builder.rb            # MODIFICADO — invoca RulesEngine en lugar de Enqueuer directo

app/controllers/admin/
└── rules_controller.rb             # OPCIONAL: CRUD básico (consola Rails es suficiente para US3)

db/migrate/
├── 20260512000001_create_notification_rules.rb
├── 20260512000002_create_pending_digests.rb
└── 20260512000003_add_rate_limit_index_on_audit.rb

lib/tasks/
└── digest_scheduler.rake           # digest_scheduler:run[batch_size,sleep_interval]

spec/central/decisioning/           # NUEVO
spec/central/broker/digest_scheduler_spec.rb
spec/integration/rules_pipeline_spec.rb
```

## Complexity Tracking

| Decisión | Por qué necesaria | Alternativa más simple rechazada porque |
|---|---|---|
| Cache layer separada (`RuleCache`) en lugar de inline en RulesEngine | Aislamiento: el motor no debe saber si la fuente es Rails.cache, Redis directo o memoria de proceso. Testeable. | Inline acoplaría cache a la lógica de evaluación, dificultando swap. |
| Rate limit por query sobre `notification_audit` (no contador agregado) | Source of truth única; evita drift entre contador y realidad. | Tabla `rate_limit_counters` requiere mantenimiento manual + bug risk de doble conteo. |
| `pending_digests` con `dispatch_at` por fila (no cron fijo) | Soporta ventanas distintas por tipo sin cambios en cron. | Cron único con ventana global fuerza un único `digest_window` por sistema. |

## Phase 0 — Research

Ver `research.md` para detalle. Decisiones clave:

1. **Rails.cache vs Memcached/Redis directo** → Rails.cache (TTL 5 min). Default store funciona en test/dev; producción puede usar memcached_store sin cambios de código.
2. **Snapshot de regla en `pending_digests`** → guardar `rule_snapshot` JSONB en la fila al insertar, para sobrevivir al borrado de la regla (FR-010).
3. **Race condition de rate limit** → aceptada como best-effort; documentada en spec edge cases. La query usa `notification_audit` particionada con índice cubriente.

## Phase 1 — Design

### Entities (ver `data-model.md`)

- **NotificationRule**: 1 fila por `notification_type` (UNIQUE).
- **PendingDigest**: 1 fila por evento agrupable; `dispatch_at` indexado para el scheduler.
- **Decision** (value object Ruby, no tabla): `{kind: :dispatch | :digest | :filter, reason: nil | "rate_limited" | ..., rule_id: int, digest_window_seconds: int | nil}`.

### Contracts (ver `contracts/`)

- `RulesEngine.decide(event:) → Decision` — interfaz pública desde `EventBuilder`.
- `RuleCache.fetch(notification_type) → NotificationRule | nil` — lookup con TTL.
- `RuleCache.invalidate(notification_type)` — invocado desde `NotificationRule#after_save/after_destroy`.
- `DigestScheduler.process_batch(batch_size: 50) → integer` — cantidad de digests consolidados.

### Quickstart scenarios (ver `quickstart.md`)

1. Crear regla, disparar 4 envíos, observar 1 filtered.
2. Configurar digest, disparar 5 envíos, correr scheduler, observar 1 email consolidado.
3. Cambiar regla en caliente, observar nuevo comportamiento tras TTL.
