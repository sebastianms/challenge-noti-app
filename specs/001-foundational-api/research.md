# Research — 001-foundational-api

**Date**: 2026-05-10

Decisiones técnicas con sus alternativas y justificación. Cada R-NN se referencia desde `plan.md`.

---

## R-01 — Mecanismo de unicidad: Postgres UNIQUE vs. lock aplicativo

**Decisión**: `UNIQUE (idempotency_hash, created_at)` + `INSERT ... ON CONFLICT DO NOTHING RETURNING *`.

**Rationale**: la atomicidad la da el motor gratis. Sin lookup previo, sin lock distribuido, sin race condition entre nodos. Bajo concurrencia, exactamente uno de los procesos compitiendo gana; los demás reciben 0 filas devueltas y consultan el original con un `SELECT` por hash.

**Alternativas consideradas**:

| Alternativa | Por qué rechazada |
| :---- | :---- |
| Lock distribuido en Redis (`SET NX`) | Requiere Redis (no está en el stack base; agrega infra). TTL del lock difícil de afinar. |
| Advisory locks de Postgres (`pg_advisory_lock`) | Funciona pero es más caro (round-trip extra) y bloqueante. La constraint es no-bloqueante y gratis. |
| `SELECT ... FOR UPDATE` previo a INSERT | Dos queries por evento, lock pesimista. A 140 rps agrega latencia innecesaria. |
| Lock aplicativo (mutex Ruby) | Solo funciona en un proceso. Inútil con múltiples workers Puma o EC2. |

**Costo**: cero adicional al INSERT. **Beneficio**: solución correcta y atómica.

---

## R-02 — Algoritmo de hash: SHA256 vs. MD5 vs. xxHash

**Decisión**: SHA256 vía `Digest::SHA256.hexdigest`.

**Rationale**: el hash no necesita ser criptográficamente seguro contra adversarios (no estamos firmando), pero debe ser resistente a colisiones accidentales y producir un string estable. SHA256 está en la librería estándar de Ruby, su costo a 140 rps es despreciable (microsegundos por hash), y produce 64 caracteres hex que indexan bien en Postgres.

**Alternativas consideradas**:

| Alternativa | Por qué rechazada |
| :---- | :---- |
| MD5 | Más rápido pero con colisiones documentadas. A escala empresarial el riesgo, aunque bajo, es innecesario. |
| xxHash / Murmur3 | Más rápidos pero requieren gema externa. La diferencia de performance no justifica la dependencia adicional. |
| SHA1 | Igual de inseguro que MD5 a futuro; no aporta nada sobre SHA256. |
| BLAKE3 | Mejor performance pero gema no estándar; gain marginal sobre SHA256 a este volumen. |

**Costo**: ~10 µs por hash en Ruby 3.4, despreciable a 140 rps (1.4 ms/seg total). **Beneficio**: estabilidad y simplicidad.

---

## R-03 — Particionamiento de `notification_events` desde día 1

**Decisión**: tabla particionada por rango sobre `created_at`, particiones mensuales, creadas y dropeadas por job programado.

**Rationale**: aunque esta feature no genera todavía el volumen total (no hay broker ni dispatcher), esta es la tabla que recibirá 500.000 inserts/hora cuando la plataforma esté completa. Migrar de tabla plana a particionada en producción exige downtime no trivial (`pg_partman` migration o swap manual). Hacerlo desde el día 1 evita una deuda futura.

**Alternativas consideradas**:

| Alternativa | Por qué rechazada |
| :---- | :---- |
| Tabla plana, particionar después | Migración futura cara; bloquea volumen. |
| Particionar por día desde el inicio | Demasiadas particiones (~365/año) para una tabla de eventos relativamente pequeña al inicio; mensual es buen punto medio. |
| Particionar por hash | Útil para distribución pero no para retención; con tiempo es trivial dropear viejos. |

**Trade-off**: la `UNIQUE` constraint debe incluir la columna de partición (`created_at`) → el constraint efectivo es `UNIQUE(idempotency_hash, created_at)`. En la práctica esto no es un problema: si dos eventos tienen el mismo `idempotency_hash` el `window_ts` ya garantiza que `created_at` los pone en el mismo bucket de tiempo, y dentro del mismo `window_ts` solo uno gana.

**Verificación de la garantía**: el `window_ts` se trunca a 1 min UTC y entra al hash. Dos invocaciones con el mismo hash necesariamente están dentro del mismo minuto y por ende dentro de la misma partición. La unicidad lógica se preserva.

---

## R-04 — Generación del `correlation_id`: UUIDv4 vs. UUIDv7

**Decisión**: UUIDv4 vía `SecureRandom.uuid` (default de Postgres `gen_random_uuid()`).

**Rationale**: el `correlation_id` es para trazabilidad humana (búsqueda por ID en logs, soporte responde "tu ticket es abc-123-..."), no para ordenamiento temporal. UUIDv4 es el estándar más conocido y soportado.

**Alternativas consideradas**:

| Alternativa | Por qué rechazada |
| :---- | :---- |
| UUIDv7 | Tiene componente temporal ordenable, útil para insertar índices ordenados (mejor cache locality). Pero requiere gema o implementación manual en Ruby (no está en stdlib hasta Ruby 3.4 — verificable). El beneficio es marginal porque el índice es por `correlation_id` UUID y el query típico es lookup directo, no rango. |
| ULID | Similar a UUIDv7, mismas razones. |
| ID secuencial visible al usuario | Filtra información (cuántos eventos hay) y permite enumeration attacks. UUID elimina ambos problemas. |

**Cuando reconsiderar**: si los queries de auditoría se vuelven dominantes y se observa cache miss en el índice de `correlation_id`, evaluar migración a UUIDv7.

---

## R-05 — Heurística para detectar email vs. user_id

**Decisión**: `recipient.to_s.include?("@")` → si es `true`, se trata como email; si es `false`, se trata como `user_id`.

**Rationale**: cubre el 100% de los casos del enunciado y de los integradores sensatos. Los user_ids internos típicamente son numéricos (`42`) o ULIDs (`01H...`), que no contienen `@`. Los emails siempre lo contienen.

**Alternativas consideradas**:

| Alternativa | Por qué rechazada |
| :---- | :---- |
| Validación estricta de email (regex RFC 5322) | El integrador podría pasar un user_id alfanumérico con `@` por error y la regex correcta lo rechazaría con mensaje confuso. La heurística simple falla en menos casos. La validación estricta queda en el `EmailChannel` cuando intente enviar. |
| Forzar al integrador a indicar el tipo (`recipient_type:`) | Agrega fricción. La heurística cubre el 100% de los casos prácticos. |
| Inferir desde el contexto de la clase (notificación email-only vs multi-canal) | Posible a futuro pero overhead innecesario para esta feature. |

**Casos límite documentados**:
- Si un integrador pasa un email malformado sin `@`, se tratará como user_id y fallará en el dispatch posterior con un error claro de "user_id no encontrado".
- Si un user_id contiene `@` (poco probable pero posible), se tratará como email. Documentado en la guía de integración: **los user_ids no deben contener `@`**.

**Implementación**:

```ruby
class RecipientNormalizer
  def self.normalize(input)
    str = input.to_s.strip
    raise ArgumentError, "recipient blank" if str.empty?
    raise ArgumentError, "recipient too long" if str.length > 320  # RFC 5321

    if str.include?("@")
      { type: :email, canonical: str.downcase }
    else
      { type: :user_id, canonical: str }
    end
  end
end
```
