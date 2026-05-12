# Implementation Plan: UI Admin — Auditoría + Blacklist

**Branch**: `007-admin-ui-audit-blacklist` | **Date**: 2026-05-12

## Summary

Migrar `/admin/audits` y `/admin/blacklist` de HTTP Basic a Devise (Phase 7), agregar vista detalle de timeline por `correlation_id`, filtros `reason`/`rule_id`, export CSV en ambos módulos, y registrar `removed_by = current_admin_user.email` en el audit trail de blacklist.

## Technical Context

**Language/Version**: Ruby 3.3 + Rails 8.1
**Primary Dependencies**: Devise (ya instalado), AuditSearch (servicio existente), CSV (stdlib)
**Storage**: PostgreSQL 17 (sin cambios de schema)
**Testing**: RSpec 3 + Capybara (request specs)
**Target Platform**: Linux + Docker

## Constitution Check

- `mission.md` SC: "soporte responde un caso en < 30s" → cubierto por SC-001/FR-003.
- `tech-stack.md`: Rails-rendered + Devise + Hotwire → todas las decisiones siguen este stack. No se introduce SPA ni nuevo framework.
- `roadmap.md` Phase 8: "Auditoría + Blacklist con timeline, filtros, payload, regla aplicada y CSV" → cubierto 1:1.
- ADL-011 (Devise): se extiende `PERMISSIONS` con secciones `:audits` y `:blacklist_read` / `:blacklist_write`. Sin nuevo ADL salvo que aparezca un trade-off no cubierto (CSV streaming → posible ADL-012).

## Design (Phase 1)

### Controllers

- `Admin::AuditsController` (heredar de `Admin::BaseController` con `controller_section = :audits`):
  - `index` — actual + filtros `reason`/`rule_id`, format `.csv` para export.
  - `show` — recibe `correlation_id` (param), renderiza timeline + payload + rule link.
- `Admin::BlacklistController` (heredar de `Admin::BaseController`):
  - `controller_section` retorna `:blacklist_read` o `:blacklist_write` según action (override `authorize_section!` o usar dos checks).
  - `index` — actual + format `.csv`.
  - `create`/`destroy` — sin HTTP Basic decode; `removed_by = current_admin_user.email`.

### RoleAuthorizer

```ruby
PERMISSIONS = {
  "admin"       => %i[dashboard rules mock_data audits blacklist_read blacklist_write].freeze,
  "product"     => %i[dashboard rules audits blacklist_read].freeze,
  "engineering" => %i[dashboard audits blacklist_read].freeze,
  "support"     => %i[dashboard audits blacklist_read blacklist_write].freeze
}
```

### Routes

- `resources :audits, only: [:index, :show]` con `param: :correlation_id` (o usar query param + `collection`); más simple: `get "audits/:correlation_id" => "audits#show"`.
- `resources :blacklist` mantiene CRUD; agregar `collection { get :export }` si conviene separar CSV (alternativa: `format :csv` en index).

### Helpers / Services

- `Admin::AuditCsv.stream(items)` — genera CSV row-by-row con `Enumerator` para usar con `response.stream` o `send_data`.
- `Admin::BlacklistCsv.stream(items)`.
- Para start simple, usar `send_data` con `CSV.generate` y `find_each(batch_size: 500)`; promover a streaming si benchmark muestra > 5s.

### Vistas

- `app/views/admin/audits/show.html.erb` — timeline component (lista ordenada con badges por status).
- `app/views/admin/audits/index.html.erb` — agregar inputs `reason`, `rule_id` + botón "Exportar CSV" que llama `?format=csv`.
- `app/views/admin/blacklist/index.html.erb` — botón "Exportar CSV".

## Project Structure

```
app/
  controllers/admin/
    audits_controller.rb       (refactor)
    blacklist_controller.rb    (refactor)
  policies/admin/
    role_authorizer.rb         (extend PERMISSIONS)
  services/admin/
    audit_csv.rb               (new)
    blacklist_csv.rb           (new)
  views/admin/
    audits/show.html.erb       (new)
    audits/index.html.erb      (modify)
    blacklist/index.html.erb   (modify)
specs/007-admin-ui-audit-blacklist/
  spec.md, plan.md, tasks.md, data-model.md, quickstart.md
spec/
  requests/admin/audits_controller_spec.rb       (extend)
  requests/admin/blacklist_controller_spec.rb    (extend)
  integration/admin_ui_audit_blacklist_spec.rb   (new)
```

## Complexity Tracking

No violations. Reuso de servicios existentes (AuditSearch, RoleAuthorizer, BaseController) y solo extensiones.
