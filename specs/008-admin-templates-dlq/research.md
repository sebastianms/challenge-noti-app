# Research — 008-admin-templates-dlq

## R1 — Engine de interpolación para templates

**Decisión**: Implementar un interpolator propio mínimo (`{{key}}` → `context[key.to_sym]`) en lugar de adoptar Liquid o Mustache.

**Rationale**:
- El scope de templates en MVP es texto plano con sustitución simple. Liquid agrega control flow (`{% if %}`, `{% for %}`) que abre superficie de seguridad (template injection si en el futuro algún copy viene de input externo).
- Liquid pesa ~600 KB y otra dependencia que mantener actualizada en CI.
- Mustache es más liviano pero igualmente innecesario para 1 sintaxis.
- Una regex `\{\{(\w+)\}\}` + `gsub` con captura de keys faltantes resuelve los 4 acceptance scenarios en ~15 líneas testeables.

**Alternativas descartadas**:
- **Liquid**: overkill + superficie de seguridad.
- **ERB**: ejecuta Ruby arbitrario — descartado por riesgo de eval.
- **Mustache**: dependencia adicional sin valor extra sobre regex propia.

---

## R2 — Cache de templates: estrategia y TTL

**Decisión**: Reusar el patrón de `RuleCache` ([ADL-008](../../.design-logs/ADL-008-rails-cache-rule-strategy.md)) — `Rails.cache.fetch(key, expires_in: 5.minutes)` con invalidación sincrónica via callbacks AR.

**Rationale**:
- Mismo perfil de carga que reglas: lectura altísima (cada send) / escritura baja (admin manual).
- 5 min TTL ya está validado en producción simulada de Phase 5 (cache hit rate > 95%).
- Invalidación sincrónica garantiza propagación inmediata ante ediciones manuales sin esperar TTL.
- Cache key sugerida: `"notification_template/#{type}/#{locale}"`.

**Alternativas descartadas**:
- **Sin cache** (consulta DB siempre): 1 query extra por envío × 140 rps = 140 qps innecesarios sobre Postgres.
- **Cache infinito + bust manual**: fragil ante deploy de múltiples workers.
- **`Rails.cache` con `read/write` explícito en lugar de `fetch`**: race window entre check-and-set.

---

## R3 — Reintento masivo: cap y transaccionalidad

**Decisión**: Cap duro de 500 items por click, `UPDATE … WHERE id IN (SELECT … FOR UPDATE SKIP LOCKED LIMIT 500)` en una transacción.

**Rationale**:
- 500 es ~1/3 de la capacidad de un batch típico del Worker (Phase 3 procesa hasta 50/batch × varios workers). Mover 500 a `pending` no satura.
- `FOR UPDATE SKIP LOCKED` evita conflictos con workers que estén procesando jobs `in_flight` o ya escaló a `pending` por otro admin.
- Una sola transacción + 1 audit consolidado mantiene el log limpio (1 fila por bulk vs 500 filas individuales).
- Si hay > 500 items, mensaje en UI "se reintentaron 500 de N; ejecutá de nuevo" — operación idempotente.

**Alternativas descartadas**:
- **Sin cap**: una DLQ de 10k items inundaría `dispatch_queue` y degradaría latencia del Worker.
- **Background job (Sidekiq) para bulk retry**: el monolito no tiene Sidekiq aún; agregar gem entera por una operación admin manual es desproporcionado.
- **Cursor pagination del bulk**: complejidad mayor que "click de nuevo".

---

## R4 — `last_error_class`: extracción vs columna dedicada

**Decisión**: En MVP, extraer en SQL con `split_part(last_error, ':', 1)` y fallback `'Unknown'`. Diferir columna dedicada a iteración futura.

**Rationale**:
- Formato actual de `last_error` (Phase 3 Worker) es `"Net::OpenTimeout: execution expired"` — `split_part` resuelve el 95% de casos.
- Agregar columna `last_error_class` requiere migration + backfill + cambio en Worker — fuera de scope de UI.
- Si el grouping resulta ruidoso post-deploy, se planifica como tarea de Phase 10.

**Alternativas descartadas**:
- **Columna dedicada ahora**: scope creep, retrasa entrega.
- **Regex en Ruby + groupby en memoria**: no escala si DLQ tiene > 10k items.

---

## R5 — Preview en vivo: turbo-frame vs JS client-side

**Decisión**: Turbo-frame con form submission a `/admin/templates/:id/preview` que renderiza `_preview.html.erb`.

**Rationale**:
- Stack del proyecto es Hotwire (sin SPA). Turbo-frame es la herramienta nativa.
- El interpolator vive server-side (mismo path que producción) → preview garantiza paridad con runtime real.
- JS client-side requeriría replicar la regex en JavaScript y mantenerla en sync — drift garantizado.

**Alternativas descartadas**:
- **Stimulus + fetch JSON**: más código por mínimo valor.
- **Submit completo + recarga**: rompe UX (pierde foco del campo).
