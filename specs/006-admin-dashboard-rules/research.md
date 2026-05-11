# Research — 006-admin-dashboard-rules

## R1 — Auth: Devise vs. has_secure_password manual

**Decisión**: usar Devise (`~> 4.9`).

**Rationale**: el spec pide email/password + lockable + intentos fallidos + sesiones + paranoid login. Devise lo provee out of the box (`database_authenticatable`, `lockable`, `trackable`, `validatable`). Implementarlo a mano requiere ~150 líneas de plumbing que no aportan valor de negocio y agregan superficie a auditar.

**Alternativas consideradas**:
- `has_secure_password` + sesión manual: 4× más código sin beneficios; perdemos lockable/trackable.
- `rodauth`: técnicamente superior pero menos canónico en monolitos Rails 8; curva de aprendizaje innecesaria para este alcance.
- OmniAuth + Google: deferido al "Roadmap evolutivo" del propio `roadmap.md`.

## R2 — Autorización: gem vs. plain Ruby

**Decisión**: plain Ruby `Admin::RoleAuthorizer` (objeto de política) en lugar de Pundit/CanCan.

**Rationale**: 4 roles × 4 secciones es una tabla estática. Una gem añade DSL+inicializador+convenciones para resolver una matriz de 16 booleans. Plain Ruby resuelve esto en 20 líneas y un test exhaustivo.

**Alternativas consideradas**:
- **Pundit**: bueno cuando hay autorización por instancia (e.g. "este usuario puede editar este post"); aquí es solo por sección.
- **CanCan**: DSL más pesado, mantenimiento incierto.

## R3 — KPIs del dashboard: queries directas vs. vista materializada

**Decisión**: queries directas con `GROUP BY` sobre `notification_audit` + cache `solid_cache` 30s.

**Rationale**: SC-002 exige < 2s con 10k filas en ventana 24h. `notification_audit` está particionado por mes (ADL-003) con índices por `(notification_type, created_at)` y `(status, created_at)` — un `GROUP BY` con filtro de ventana 24h cae en una sola partición y se resuelve en < 100ms a esa cardinalidad. Vistas materializadas agregan complejidad operativa (refresh, locks); reservado para Phase 10 si el volumen crece.

**Alternativas consideradas**:
- Vista materializada con refresh por job: descartado por complejidad operativa.
- Sin cache: cada refresh del navegador pega 3 queries; aceptable pero costoso si hay polling.

## R4 — Chartkick + groupdate

**Decisión**: adoptar `chartkick` + `groupdate`.

**Rationale**: el dashboard pide 1 bar chart y 1 pie chart. Chartkick es 1 línea de view (`<%= bar_chart data %>`) con Chart.js via importmap. Sin chartkick, escribir el JS a mano son ~50 líneas que no aportan valor.

**Alternativas consideradas**:
- D3 puro: overkill.
- Tablas sin gráficos: cumpliría FR pero pierde el factor "visible al stakeholder".

## R5 — Diff de cambios para audit trail

**Decisión**: usar `ActiveModel::Dirty#previous_changes` capturado en el callback `after_save`/`after_destroy` y persistido vía `RuleChange.create!` dentro de la misma transacción.

**Rationale**: Rails entrega el diff resuelto y tipado; reescribirlo manualmente es propenso a errores con tipos JSONB (`channels TEXT[]`).

**Implementación**: el controller invoca `rule.save!` y luego `RuleChange.create!(notification_rule: rule, admin_user_id: current_admin_user.id, action:, before:, after:)` con el diff. Wrapper en `ActiveRecord::Base.transaction`.

**Alternativas consideradas**:
- `paper_trail` gem: pesado para un único modelo; requiere su propia tabla `versions` con mucho más de lo que necesitamos.
- Triggers SQL: violan el principio "monolito Rails idiomático".

## R6 — Feature flag para mock data: ENV vs. tabla

**Decisión**: ENV var `ALLOW_MOCK_DATA_FEATURE` leída en un initializer (`Rails.application.config.allow_mock_data_feature = ENV.fetch("ALLOW_MOCK_DATA_FEATURE", "true") != "false"`).

**Rationale**: la decisión "feature on/off" es deployment-time, no runtime configurable por usuario. ENV es el patrón canónico (ya usado por `AUDIT_BASIC_AUTH_*`, `SENDGRID_*`, `AUDIT_RETENTION_MONTHS`).

**Defensa en profundidad**: además de ocultar el botón, el controller verifica el flag y responde 403 si está off (FR-017). Esto previene que un admin que conoce la ruta haga POST manual con el flag desactivado.

**Alternativas consideradas**:
- Tabla `feature_flags`: overkill, requiere UI para togglear.
- `Rails.env.production?`: descartado porque queremos el flag para staging/demo, no solo dev/test.

## R7 — Idempotencia del MockDataGenerator

**Decisión**: cada recurso del generador usa la estrategia de idempotencia más natural:
- Reglas: `find_or_create_by(notification_type:)` — la tabla ya tiene UNIQUE en `notification_type`.
- Blacklist: `insert_all([{...}], unique_by: :idx_blacklist_unique)` — reusa el patrón de ADL-010.
- Audits + queue items: SIEMPRE se agregan (correlation_id aleatorio); no son idempotentes pero sí inocuos.

**Rationale**: el spec (US4 escenario 6) pide explícitamente "se agregan más envíos/audits sin duplicar reglas". Esta política refleja la intención: reglas son configuración (1 sola), audits son tráfico (acumulable).

## R8 — RuleChange con FK SET NULL

**Decisión**: `notification_rule_id` referencia a `notification_rules(id) ON DELETE SET NULL`.

**Rationale**: queremos preservar el historial de reglas borradas (auditoría de compliance). Sin SET NULL, el delete cascadea y se pierde la traza. La acción `deleted` en `rule_changes` guarda `before = snapshot completo` y `after = NULL`, así el detalle queda en la fila aunque la regla original ya no exista.
