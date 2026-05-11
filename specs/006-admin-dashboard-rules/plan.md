# Implementation Plan: 006-admin-dashboard-rules

**Branch**: `main` (single-branch flow del repo) · **Date**: 2026-05-11

## Summary

Primera UI de stakeholders. Devise + `admin_users(role)` reemplaza el HTTP Basic actual del MVP en las nuevas rutas (audits/blacklist quedan como están, migrarán en Phase 8). Dashboard renderiza 4 KPIs con queries directas a `notification_audit` + `dispatch_queue` cacheadas 30s en `solid_cache`. CRUD de reglas reusa `NotificationRule` existente y persiste un audit trail completo en `rule_changes` dentro de la transacción del cambio. Botón "Generar Data Mock" gated por `ALLOW_MOCK_DATA_FEATURE` (default visible) llama a un `MockDataGenerator` idempotente.

## Technical Context

- **Language/Version**: Ruby 3.3 + Rails 8.1
- **Primary Dependencies (nuevas)**: `devise ~> 4.9`, `chartkick ~> 5.1`, `groupdate ~> 6.4` (queries por intervalo para volumen 24h)
- **Storage**: PostgreSQL 17 (mismo); 2 tablas nuevas: `admin_users`, `rule_changes`
- **Cache**: `solid_cache` (ya presente) — TTL 30s para KPIs
- **Testing**: RSpec + FactoryBot + shoulda-matchers (mismo stack)
- **UI**: Hotwire (Turbo + Stimulus) + ERB; Chartkick + Chart.js via importmap
- **Target Platform**: Mismo (Linux/Docker, Puma)
- **Project Type**: Monolito Rails

## Constitution Check

- **mission.md**: feature satisface R5 (motor de reglas visible) y abre el camino para R6/R8 visibles en Phase 8. ✅
- **tech-stack.md**: Devise está alineado con la decisión "monolito Rails idiomático"; no introduce un servicio externo de auth. Chartkick es una librería view-layer, no toca el core. ✅
- **roadmap.md**: Phase 7 es la siguiente fase pendiente. ✅
- **ADLs previos**: ADL-008 (RuleCache via `Rails.cache`) y ADL-007 (auth de webhook) no se contradicen. Nuevo ADL-011 documentará la decisión Devise vs. HTTP Basic + por qué `admin_users` y no extender ENV.

No hay violaciones que justifiquen Complexity Tracking.

## Project Structure

```
app/
├─ controllers/admin/
│  ├─ sessions_controller.rb           # NUEVO — Devise sessions custom (mensaje genérico)
│  ├─ dashboard_controller.rb          # NUEVO — KPIs
│  ├─ rules_controller.rb              # NUEVO — CRUD + history action
│  └─ mock_data_controller.rb          # NUEVO — POST /admin/mock_data
├─ central/decisioning/
│  └─ rule_change.rb                   # NUEVO — modelo del audit trail
├─ models/
│  └─ admin_user.rb                    # NUEVO — Devise model
├─ services/admin/
│  ├─ dashboard_metrics.rb             # NUEVO — calcula los 4 KPIs (cacheable)
│  └─ mock_data_generator.rb           # NUEVO — siembra demo data idempotente
├─ policies/admin/
│  └─ role_authorizer.rb               # NUEVO — gate por rol (Pundit-less, plain Ruby)
├─ views/admin/
│  ├─ sessions/new.html.erb            # NUEVO
│  ├─ dashboard/index.html.erb         # NUEVO
│  ├─ rules/
│  │  ├─ index.html.erb                # NUEVO
│  │  ├─ new.html.erb                  # NUEVO
│  │  ├─ edit.html.erb                 # NUEVO
│  │  ├─ _form.html.erb                # NUEVO
│  │  └─ history.html.erb              # NUEVO
│  └─ shared/
│     └─ _mock_data_button.html.erb    # NUEVO — partial gated por feature flag
config/
├─ initializers/devise.rb              # NUEVO (generado por devise)
├─ initializers/mock_data_feature.rb   # NUEVO — lee ENV → constante
└─ routes.rb                           # MOD — devise_for + namespace admin
db/migrate/
├─ NNNN_devise_create_admin_users.rb   # NUEVO
└─ NNNN_create_rule_changes.rb         # NUEVO
spec/
├─ models/admin_user_spec.rb
├─ central/decisioning/rule_change_spec.rb
├─ services/admin/dashboard_metrics_spec.rb
├─ services/admin/mock_data_generator_spec.rb
├─ controllers/admin/sessions_controller_spec.rb
├─ controllers/admin/dashboard_controller_spec.rb
├─ controllers/admin/rules_controller_spec.rb
├─ controllers/admin/mock_data_controller_spec.rb
└─ integration/admin_ui_spec.rb        # smoke end-to-end de US1/US2/US3/US4
.design-logs/
└─ ADL-011-devise-admin-users-and-roles.md  # NUEVO
```

## High-level approach por user story

### US1 — Auth + roles

- `admin_users` con Devise modules: `database_authenticatable, recoverable, rememberable, validatable, lockable, trackable`. Columna `role` (CHECK IN `admin/product/support/engineering`).
- `Admin::SessionsController < Devise::SessionsController` override para mensaje genérico (`config.paranoid = true` en devise).
- Authorization: `Admin::RoleAuthorizer.allow!(user, section:)` — plain Ruby, mapeo `{admin: %i[dashboard rules mock_data], product: %i[dashboard rules], engineering: %i[dashboard], support: %i[dashboard]}`. `before_action :authorize_section!` en cada controller admin.
- 403 vía `render "errors/forbidden", status: :forbidden`.

### US2 — Dashboard

- `Admin::DashboardMetrics.new(window: 24.hours).snapshot` → Hash con 4 secciones. Internamente:
  - **Volumen**: `NotificationAudit.where(status: "dispatched", created_at: 24.h.ago..).group(:notification_type, :metadata->>'channel').count` (channel se infiere del audit dispatched metadata; fallback "email" si null).
  - **Tasa de filtrado**: `NotificationAudit.where(status: "filtered", created_at: 24.h.ago..).group("metadata->>'reason'").count`.
  - **Queue depth**: `DispatchQueueRecord.where(status: "pending").count`; **DLQ**: `where(status: "dlq").count`. En vivo (no cache).
  - **Error rate**: por canal, `failed / total` en ventana.
- Cache: `Rails.cache.fetch("dashboard:snapshot:v1", expires_in: 30.s)` envuelve los 3 KPIs cacheables; queue depth se calcula fuera.
- View con Chartkick (`bar_chart`, `pie_chart`) + 2 contadores grandes.

### US3 — CRUD reglas + audit trail

- `Admin::RulesController` con acciones estándar + `history`. Form usa los validators ya existentes de `NotificationRule`.
- `RuleChange` (nuevo modelo): `notification_rule_id` (nullable, FK con `ON DELETE SET NULL`), `admin_user_id`, `action` (CHECK IN created/updated/deleted), `before JSONB`, `after JSONB`, `changed_at`.
- Persistencia: `ActiveRecord::Base.transaction do; rule.save!; RuleChange.create!(...); end`. Diff calculado con `rule.previous_changes` (before = valores antes, after = valores después).
- Vista `history.html.erb` renderiza diff campo-a-campo (helper `diff_row(before, after, key)`).
- `RuleCache` se invalida automáticamente por callbacks existentes (no se toca).

### US4 — Mock data

- `Admin::MockDataController#create` chequea:
  1. `ALLOW_MOCK_DATA_FEATURE == true` (default si unset) — sino 403.
  2. `current_admin_user.role == "admin"` — sino 403.
- Si pasa: `Admin::MockDataGenerator.new(seed: SecureRandom.hex(4)).call` y redirige al referrer con flash success.
- `MockDataGenerator` crea idempotentemente:
  - 3 reglas: birthday (digest 5m), mfa (critical, sin digest), marketing (max_per_day=1) → `find_or_create_by(notification_type:)`.
  - 50 audits con mix `delivered/failed/filtered` distribuidos en últimas 24h.
  - 5 dispatch_queue pending, 2 dlq.
  - 3 blacklist entries (idempotentes vía unique key).
- Partial `_mock_data_button.html.erb` consulta `MockDataFeature.enabled?` y `current_admin_user&.role == "admin"`.

## Constitution Re-Check after design

- ✅ Sin nuevas violaciones.
- ✅ Devise reemplaza HTTP Basic solo en rutas nuevas; las existentes (`/admin/audits`, `/admin/blacklist`) NO se migran en esta fase (deferido a Phase 8 según roadmap).
- ✅ El feature flag sigue el patrón existente (env-based, sin tabla).
- ✅ Performance: KPIs cacheados 30s; queue depth es count rápido sobre índice existente.

## Complexity Tracking

(Vacío — no hay violaciones a justificar)
