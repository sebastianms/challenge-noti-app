# ADL-002: Usar structure.sql en lugar de schema.rb por tablas particionadas

**Fecha:** 2026-05-10
**Estado:** Activo
**Área:** Base de Datos
**Autor:** AI Session

---

## Contexto

Rails genera por defecto `db/schema.rb` como representación del esquema de la base de datos. Sin embargo, `schema.rb` usa la DSL de ActiveRecord que no puede representar fielmente todas las funcionalidades de PostgreSQL. Al crear `notification_events` como tabla particionada (`PARTITION BY RANGE (idempotency_window_ts)`), Rails intentó volcar la partición default (`notification_events_default`) usando `INHERITS`, lo que Postgres prohíbe para tablas con particionamiento declarativo. El resultado fue un `schema.rb` inválido que causaba errores al correr `db:test:load_schema`.

---

## Decisión

Cambiar `config.active_record.schema_format = :sql` en `config/application.rb` para que Rails use `db/structure.sql` (generado vía `pg_dump`) en lugar de `db/schema.rb`.

---

## Justificación

`structure.sql` es un dump SQL nativo de PostgreSQL que preserva fielmente: tablas particionadas, constraints CHECK, secuencias, índices concurrentes, y cualquier otra extensión Postgres. `schema.rb` solo puede representar el subconjunto de funcionalidades que ActiveRecord conoce, excluyendo `PARTITION BY RANGE`.

---

## Consecuencias

### ✅ Positivas
- El esquema refleja exactamente lo que existe en la base de datos real.
- Compatible con cualquier funcionalidad nativa de PostgreSQL sin restricciones.
- `db:test:load_schema` carga el esquema correcto en CI y local.

### ⚠️ Trade-offs aceptados
- Requiere `pg_dump` instalado localmente (`postgresql-client`) para que `db:schema:dump` funcione.
- `structure.sql` es menos legible que `schema.rb` para revisión en PRs.
- CI ya tiene `pg_dump` disponible via la imagen `postgres:17-alpine` como service; no requiere cambios en el workflow.
- Los desarrolladores nuevos deben instalar `postgresql-client` en sus máquinas.

---

## Alternativas Consideradas

| Alternativa | Razón de descarte |
|-------------|-------------------|
| Mantener `schema.rb` y evitar particionamiento nativo | El particionamiento por `idempotency_window_ts` es un requisito de diseño central (ADL-001); eliminarlo compromete la estrategia de idempotencia y performance. |
| Gestionar particiones fuera de Rails (scripts externos) | Añade complejidad operativa sin beneficio real; `structure.sql` resuelve el problema de forma estándar. |

---

## Decisiones Relacionadas
- [ADL-001: Partition key idempotency_window_ts](.design-logs/ADL-001-partition-key-idempotency-window-ts.md) — Esta decisión es consecuencia directa del particionamiento definido en ADL-001.

---

## Notas para el AI (Memoria Técnica)
- No revertir a `schema_format = :ruby`. El proyecto usa tablas particionadas que son incompatibles con `schema.rb`.
- Si se agrega una nueva funcionalidad Postgres nativa (funciones, triggers, tipos personalizados), seguirá funcionando correctamente con `structure.sql` sin cambios adicionales.
- Al incorporar un desarrollador nuevo, indicar que debe instalar `postgresql-client-16` (`sudo apt install postgresql-client-16`) para poder correr `db:schema:dump` localmente.
- En CI (`.github/workflows/ci.yml`), `pg_dump` está disponible automáticamente por el service `postgres:16-alpine`; no requiere paso adicional de instalación.
