# ADL-013 — Template Override Resolver (Phase 9)

**Fecha**: 2026-05-12
**Estado**: Aceptado
**Feature**: [008-admin-templates-dlq](../specs/008-admin-templates-dlq/)

---

## Contexto

`AbstractNotification.title/body` eran métodos de interfaz definidos en la clase base pero nunca invocados en el pipeline de despacho. El `SendgridAdapter` leía `event_payload["subject"]` y `"body"` del JSON almacenado en `notification_events.payload`, que era la serialización directa del `context` hash del llamante. Esto dejaba `title` y `body` como dead code efectivo y hacía imposible overridear el copy sin redeploy.

---

## Decisión

### Arquitectura de resolución

Introducir tres capas:

1. **`Templates::TemplateInterpolator`** — reemplazador `{{key}}` → `context[key]` con reporte de variables faltantes. Implementación propia (regex + `gsub`) en lugar de Liquid o Mustache.

2. **`Templates::TemplateCache`** — wrapper `Rails.cache.fetch(key, expires_in: 5.minutes)` con invalidación sincrónica via callbacks `after_save`/`after_destroy` de `NotificationTemplate`. Mismo patrón que `RuleCache` ([ADL-008](ADL-008-rails-cache-rule-strategy.md)).

3. **`Templates::TemplateResolver`** — consulta cache → DB; retorna `nil` si no hay override.

`AbstractNotification.send` resuelve `subject`/`body` antes de pasar el contexto a `EventBuilder`:

```ruby
def resolved_context(context)
  type    = resolved_notification_type
  subject = Templates::TemplateResolver.title_for(type: type, ctx: context) || title(context)
  resolved_body = Templates::TemplateResolver.body_for(type: type, ctx: context) || body(context)
  context.merge(subject: subject, body: resolved_body)
end
```

`SendgridAdapter` ya leía `event_payload["subject"]` / `"body"]` — sin cambios al canal.

---

## Por qué interpolator propio vs Liquid/Mustache

| Criterio | Propio (`{{key}}` regex) | Liquid | Mustache |
|----------|--------------------------|--------|----------|
| Dependencias nuevas | 0 | +1 gem ~600 KB | +1 gem |
| Superficie de seguridad | Mínima (solo sustitución) | Media (control flow `{% if %}`) | Baja |
| Soporte de condicionales | No | Sí | Parcial |
| Líneas de código | ~15 | ~0 (usa gem) | ~0 |
| Paridad server/preview | Garantizada | Garantizada | Garantizada |

Para el scope actual (copy plano con variables simples), la regex propia cubre todos los casos. El umbral de migración a Liquid es cuando se necesiten condicionales o loops en templates — decisión diferida.

---

## Compatibilidad hacia atrás

- Sin override en DB → `TemplateResolver` retorna `nil` → `AbstractNotification.title/body` son invocados como antes. Cero cambios en comportamiento existente.
- `BrokenNotification` (sin `title`/`body`) lanza `NotImplementedError` igual que antes — la interface se preserva.

---

## Consecuencias

**Positivas**:
- Producto puede cambiar copy en < 5 min sin deploy.
- `title`/`body` de `AbstractNotification` pasan de dead code a punto de extensión real.
- Cache con invalidación sincrónica garantiza propagación inmediata.

**Negativas / Trade-offs**:
- Sin cache en `test` environment (`null_store`) — los specs de resolución no pueden verificar hit rate; se testea comportamiento funcional.
- `merge(subject:, body:)` sobrescribe claves `:subject`/`:body` si el llamante las pasaba explícitamente — comportamiento esperado (override toma prioridad).

---

## Referencias

- [ADL-008](ADL-008-rails-cache-rule-strategy.md) — patrón de cache con invalidación sincrónica.
- [specs/008-admin-templates-dlq/research.md](../specs/008-admin-templates-dlq/research.md) — R1 (interpolator), R2 (cache), R5 (preview turbo-frame).
