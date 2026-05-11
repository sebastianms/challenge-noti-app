# Contract — RuleCache

```ruby
module Central::Decisioning
  class RuleCache
    TTL = 5.minutes

    # Retorna la regla activa para el tipo, o nil.
    # Lee de Rails.cache; en miss consulta BD y cachea TTL.
    #
    # @param notification_type [String]
    # @return [NotificationRule, nil]
    def self.fetch(notification_type); end

    # Invalida la entrada cacheada para un tipo.
    # Invocado desde after_save / after_destroy del modelo.
    #
    # @param notification_type [String]
    def self.invalidate(notification_type); end

    # (Solo para tests) limpia toda la cache de reglas.
    def self.clear_all; end
  end
end
```

## Garantías
- **Consistencia eventual**: tras editar una regla, el cache se invalida sincrónicamente. Si la invalidación falla (cache caído), el TTL de 5 min asegura recuperación.
- **Single source de verdad en miss**: usa `find_by(notification_type:, enabled: true)`. Reglas con `enabled=false` se tratan como no existentes (retorna nil).
- **Performance**: cache hit es O(1) en memoria local; cache miss es 1 query con índice parcial.

## No-garantías
- Coordinación entre procesos: si Rails.cache es `:memory_store`, cada worker tiene su propia cache. Aceptable para Phase 5 (workers en mismo container). Si se escala a múltiples nodos, swap a `:mem_cache_store` o `:redis_cache_store`.
