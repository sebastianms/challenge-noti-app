# ADL-008: Rails.cache para reglas de notificación con TTL + invalidación explícita

**Fecha**: 2026-05-12
**Estado**: Aceptado
**Feature**: 004-rules-engine (RuleCache)

## Contexto

El motor de reglas (`RulesEngine`) se invoca por cada evento ingresado. Una notificación de tráfico moderado (~100 envíos/segundo) implicaría 100 lookups/segundo a `notification_rules`, una tabla con muy pocas filas (≤ N tipos de notificación) y que cambia raramente (editada manualmente desde consola/UI).

Sin cache, la mayoría de las queries serían read-redundancy pura. Con cache, hay que decidir: ¿qué store?, ¿qué TTL?, ¿cómo invalidar al editar?

## Decisión

Usar `Rails.cache` con clave `"rule:#{notification_type}"`, TTL `5.minutes`, e invalidación explícita en `after_save`/`after_destroy` del modelo `NotificationRule`. La capa de cache vive en una clase dedicada `RuleCache` con interfaz `fetch / invalidate / clear_all`.

```ruby
Rails.cache.fetch("rule:#{type}", expires_in: 5.minutes) do
  NotificationRule.find_by(notification_type: type, enabled: true)
end
```

El TTL es la garantía de consistencia eventual (SC-001 del spec: cambios reflejados en ≤ 5 min). La invalidación explícita reduce esa latencia a cero cuando edita un proceso local.

## Alternativas consideradas

1. **Memoización a nivel proceso (`@rules ||= Hash.new`)**: descartada. Cada worker tendría una vista distinta; sin TTL ni invalidación cross-process. Cambios requerirían reiniciar workers — exactamente lo que esta feature elimina.
2. **Redis directo via gema `redis-rb`**: descartada. Agrega dependencia de runtime y complejidad de configuración. `Rails.cache` ya abstrae el store; producción puede swappearse a `:redis_cache_store` sin tocar código de aplicación.
3. **Consultar BD siempre + prepared statement**: descartada. Para 100 rps, 100 hits/s a una tabla read-mostly es desperdicio. El índice parcial `WHERE enabled = TRUE` ayudaría pero no compensa.
4. **Cache de larga duración + pub/sub para invalidar**: descartada por complejidad. El TTL de 5 min con invalidación local cubre el SLO del producto; un sistema pub/sub justificaría su costo solo si fueran segundos.

## Consecuencias

**Positivas**:
- 100 sends del mismo tipo → ≤ 1 query a `notification_rules` (validado en spec, SC-002).
- Cambio de regla refleja en ≤ 5 min sin reiniciar workers (consistencia eventual, SC-001).
- Swap a Redis/Memcached en producción es config, no código.
- Interfaz `RuleCache` aísla el cache de la lógica de decisión → testeable con `MemoryStore` instanciado en specs.

**Negativas / trade-offs**:
- Con `:memory_store` (default dev/test) cada worker tiene su propio cache. En multi-nodo, la invalidación local del nodo A no afecta al nodo B; este último espera al TTL. Aceptable mientras el SLO es ≤ 5 min.
- `enabled = false` se trata como "regla no existe" (retorna nil del `find_by`). Esto significa que reglas pausadas no se distinguen de reglas inexistentes en el cache; intencional según el spec (FR-001 + Assumption: deshabilitar = sin restricciones).
- `clear_all` usa `delete_matched("rule:*")`, soportado por `MemoryStore` y `RedisCacheStore` pero NO por `MemCacheStore` (sin operación de match). Si se migra a Memcached, hay que rediseñar `clear_all` (por ejemplo, mantener un set de keys conocidas). No bloqueante hoy.

## Referencias

- Implementación: `app/central/decisioning/rule_cache.rb`
- Modelo con callbacks: `app/central/decisioning/notification_rule.rb`
- Tests: `spec/central/decisioning/rule_cache_spec.rb`
- Spec de hit rate: `spec/integration/rules_pipeline_spec.rb` (escenario 7)
