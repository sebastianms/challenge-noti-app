# Implementation Plan: 008-admin-templates-dlq

**Branch**: `main` (trunk-based) | **Date**: 2026-05-12

## Summary

Cerrar el set de capacidades operativas del panel admin agregando: (1) un editor de templates DB-backed con override sobre `AbstractNotification` y preview en vivo; (2) una vista de DLQ agrupada por motivo con reintento individual/masivo (cap 500) y descarte auditado. Stack: Rails 8.1 + Devise + Hotwire, mismas convenciones de Phase 7/8.

## Technical Context

- **Language/Version**: Ruby 3.3 / Rails 8.1
- **Primary Dependencies**: Devise (auth), Hotwire (UI), `Rails.cache` (override cache), Postgres 17 (`dispatch_queue` con índice parcial existente)
- **Storage**: PostgreSQL 17 — nueva tabla `notification_templates`; extender CHECK de `dispatch_queue.status` para aceptar `discarded`
- **Testing**: RSpec, FactoryBot, WebMock — cobertura ≥ 90%
- **Target Platform**: Linux / Docker
- **Project Type**: Rails monolith

## Constitution Check

| Gate | Status |
|------|--------|
| Alineado con `mission.md` (configurar sin código, observabilidad operativa) | ✅ |
| Alineado con `tech-stack.md` (Rails + Hotwire + Devise; nada nuevo) | ✅ |
| Consistente con `roadmap.md` Phase 9 (Templates + DLQ) | ✅ |
| Reutiliza patrones existentes (cache → ADL-008, audit metadata → ADL-012, RoleAuthorizer → ADL-011) | ✅ |
| Sin dependencias nuevas | ✅ |

Sin violaciones — Complexity Tracking no aplica.

## Architecture

### Templates

```
AbstractNotification.title(ctx)
   └─ TemplateResolver.title_for(type:, ctx:)
        ├─ TemplateCache.fetch(type, locale)   ← Rails.cache, TTL 5 min
        │     └─ NotificationTemplate.find_by(notification_type:, locale:)
        ├─ override.present?
        │     └─ Mustache-lite interpolate(override.title, ctx)   → string
        └─ else: super (subclass method)
```

- `NotificationTemplate` (`app/models/notification_template.rb`): AR model con validations + callback `after_save`/`after_destroy` que llama `TemplateCache.invalidate(notification_type, locale)`.
- `TemplateCache` (`app/central/templates/template_cache.rb`): wrapper alrededor de `Rails.cache` con `fetch(type, locale, &block)` — espejo de `RuleCache`.
- `TemplateInterpolator` (`app/central/templates/template_interpolator.rb`): `interpolate(string, context) → {result:, missing: [keys]}`. Regex `\{\{(\w+)\}\}` → reemplazo; keys no resueltas → vacío + reporte.
- `AbstractNotification` se modifica: `title`/`body`/`digest_template` consultan `TemplateResolver` antes de delegar a los métodos de la subclase.

### DLQ

```
Admin::DlqController < Admin::BaseController
   controller_section = :dlq
   ├─ index   → DlqQuery.grouped_by_reason → render lista
   ├─ retry   (member)  → DlqRetrier.call(item, by: current_admin_user)
   ├─ bulk_retry (collection) → DlqRetrier.bulk_call(reason:, by:, cap: 500)
   └─ discard (member)  → DlqDiscarder.call(item, reason:, by:)
```

- `Admin::DlqQuery` (`app/central/admin/dlq_query.rb`): scope `dispatch_queue.where(status: 'dead')` con `GROUP BY` derivado de `last_error_class` (calculada en SQL extrayendo el prefijo del `last_error` con `split_part`).
- `Admin::DlqRetrier` (`app/central/admin/dlq_retrier.rb`): operaciones transaccionales. Individual: 1 UPDATE + 1 audit. Bulk: `UPDATE … WHERE status='dead' AND last_error LIKE '<class>%' LIMIT 500` (Postgres no soporta `LIMIT` en `UPDATE`; usar subquery `WHERE id IN (SELECT … FOR UPDATE SKIP LOCKED LIMIT 500)`) + 1 audit consolidado.
- `Admin::DlqDiscarder` (`app/central/admin/dlq_discarder.rb`): `UPDATE status='discarded'` + audit.
- Extender `dispatch_queue.status` CHECK: agregar `discarded`.
- Extender `RoleAuthorizer::PERMISSIONS`: agregar `:templates` (admin, product) y `:dlq` (admin, engineering).

## Project Structure

```
app/
  models/
    notification_template.rb                    # NEW
  central/
    abstract_notification.rb                    # MODIFICADO (consulta TemplateResolver)
    templates/
      template_cache.rb                         # NEW
      template_resolver.rb                      # NEW
      template_interpolator.rb                  # NEW
    admin/
      dlq_query.rb                              # NEW
      dlq_retrier.rb                            # NEW
      dlq_discarder.rb                          # NEW
  policies/admin/role_authorizer.rb             # MODIFICADO (+ :templates, :dlq)
  controllers/admin/
    templates_controller.rb                     # NEW
    dlq_controller.rb                           # NEW
  views/admin/
    templates/
      index.html.erb                            # NEW
      edit.html.erb                             # NEW (form + preview)
      _preview.html.erb                         # NEW (turbo-frame)
    dlq/
      index.html.erb                            # NEW (grouped)
config/routes.rb                                # MODIFICADO (+ resources)
db/migrate/
  20260513000001_create_notification_templates.rb       # NEW
  20260513000002_add_discarded_to_dispatch_queue.rb     # NEW
spec/
  models/notification_template_spec.rb
  central/templates/template_resolver_spec.rb
  central/templates/template_interpolator_spec.rb
  central/admin/dlq_query_spec.rb
  central/admin/dlq_retrier_spec.rb
  central/admin/dlq_discarder_spec.rb
  requests/admin/templates_controller_spec.rb
  requests/admin/dlq_controller_spec.rb
  integration/admin_ui_templates_dlq_spec.rb            # walkthrough end-to-end
.design-logs/ADL-013-template-override-resolver.md      # NEW (cache + fallback)
.design-logs/ADL-014-dlq-bulk-retry-cap.md              # NEW (cap 500 + transaccional)
```

## Risks & Mitigations

| Riesgo | Mitigación |
|--------|-----------|
| Cache stale tras edición rápida | Invalidación sincrónica `after_save`/`after_destroy` (ADL-008) |
| `last_error_class` extraída de string es frágil | Persistir `last_error_class` como columna dedicada al fallar — diferido a iteración futura; en MVP usar `split_part(last_error, ':', 1)` con fallback a `"Unknown"` |
| Bulk retry interfere con worker (race) | `UPDATE … WHERE status='dead'` filtra; el worker usa `SKIP LOCKED` en `pending` (ADL-005); sin overlap |
| Template con variable maliciosa (XSS) | Output del preview escapado con `h()` por defecto en ERB; interpolator no ejecuta código |
| Override borrado mientras hay digests pendientes | Digests usan snapshot (ADL-009) — independientes |

## Testing Strategy

- **Unit**: model validations, `TemplateInterpolator` (happy + missing keys + caracteres especiales), `DlqRetrier` individual + bulk + cap, `DlqDiscarder` validación de motivo.
- **Request**: gating por rol, redirect-to-login, format CSV (no aplica), CSRF en POST.
- **Integration**: walkthrough `admin_ui_templates_dlq_spec.rb` con admin logueado: crea override → envío usa override; injecta dead jobs → reintenta individual → bulk → descarta.
- **Coverage gate**: ≥ 90% global, módulos nuevos ≥ 95%.

## Cutover

Sin feature flag — la tabla nueva está vacía por default, así que el comportamiento es 100% backward compatible (sin overrides → todo se renderiza desde Ruby como hoy).
