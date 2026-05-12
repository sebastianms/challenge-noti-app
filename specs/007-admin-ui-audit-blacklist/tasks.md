# Tasks — 007-admin-ui-audit-blacklist

**Status**: Completado

## Setup

- [x] T001 Actualizar `Admin::RoleAuthorizer::PERMISSIONS` con `:audits`, `:blacklist_read`, `:blacklist_write` en `app/policies/admin/role_authorizer.rb`.
- [x] T002 Ajustar rutas en `config/routes.rb`: `resources :audits, only: [:index, :show], param: :correlation_id` y dejar `:blacklist` igual.

## Foundational

- [x] T003 Crear `app/services/admin/audit_csv.rb` con `Admin::AuditCsv.generate(items)` que retorna string CSV.
- [x] T004 Crear `app/services/admin/blacklist_csv.rb` con `Admin::BlacklistCsv.generate(items)`.
- [x] T005 Crear specs unitarios para ambos servicios CSV en `spec/services/admin/`.

## US3 — Migración a Devise

- [x] T006 [US3] Refactorizar `Admin::AuditsController` para heredar de `Admin::BaseController` (eliminar `http_basic_authenticate_with`, definir `controller_section = :audits`).
- [x] T007 [US3] Refactorizar `Admin::BlacklistController`: heredar de `BaseController`, dual section (lectura vs escritura), eliminar `decode_basic_user`, usar `current_admin_user.email` como `removed_by`.
- [x] T008 [US3] Spec en `spec/requests/admin/audits_controller_spec.rb`: redirect-to-login si no autenticado; 200 con admin/product/support/engineering.
- [x] T009 [US3] Spec en `spec/requests/admin/blacklist_controller_spec.rb`: 200 read para todos los roles; 403 write para product/engineering; `removed_by = current_admin_user.email` en audit `blacklist_removed`.

## US1 — Audits UX

- [x] T010 [US1] Extender `AuditSearch` (o filtrar en controller) para aceptar `reason` y `rule_id` que matcheen contra `metadata->>'reason'` y `metadata->>'rule_id'`.
- [x] T011 [US1] Implementar `AuditsController#show`: buscar por `correlation_id` (ASC timeline), exponer `@timeline`, `@payload`, `@rule` (NotificationRule.find_by(id: rule_id)).
- [x] T012 [US1] Crear `app/views/admin/audits/show.html.erb` con timeline (status, channel, timestamp, source, reason, rule link).
- [x] T013 [US1] Modificar `app/views/admin/audits/index.html.erb`: agregar inputs `reason`/`rule_id`, link "Detalle" por fila, botón "Exportar CSV".
- [x] T014 [US1] Soportar `format :csv` en `AuditsController#index` → `send_data Admin::AuditCsv.generate(@items), filename: "audits-#{Time.zone.now.strftime('%Y%m%d%H%M')}.csv"`.
- [x] T015 [US1] Spec request: filtros `reason`/`rule_id` filtran correctamente; `show` renderiza timeline con N filas; `format=csv` retorna `text/csv`.

## US2 — Blacklist UX

- [x] T016 [US2] Modificar `app/views/admin/blacklist/index.html.erb`: agregar botón "Exportar CSV".
- [x] T017 [US2] Soportar `format :csv` en `BlacklistController#index`.
- [x] T018 [US2] Spec request: `format=csv` retorna headers correctos y filas filtradas.

## Polish

- [x] T019 ADL-012 — Migración HTTP Basic → Devise para audits/blacklist (incluyendo trade-offs CSV streaming vs send_data).
- [x] T020 Actualizar `README.md`: sección Auditoría / Blacklist con nuevas rutas (Devise, no HTTP Basic), filtros nuevos, CSV export.
- [x] T021 Actualizar `specs/roadmap.md`: marcar Phase 8 como `[DONE]`.
- [x] T022 Spec de integración `spec/integration/admin_ui_audit_blacklist_spec.rb`: walkthrough US3 → US1 → US2 con un solo admin logueado.
- [x] T023 Actualizar `MiniCentral De Notificaciones.md` Anexo A con resumen Phase 8.

## DoD

- 100% verde en lint, tests, brakeman, bundler-audit.
- Cobertura ≥ 95% en módulos modificados.
- 0 rutas admin operativas con HTTP Basic.
- Walkthrough manual: support resuelve un caso real desde `/admin/audits` en < 30s.
