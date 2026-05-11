# ADL-004: CLOCK_TIMESTAMP() en lugar de NOW() para SKIP LOCKED

**Fecha**: 2026-05-11
**Estado**: Aceptado
**Feature**: 002-email-dispatch (Worker / dispatch_queue)

## Contexto

`Worker.process_batch` reclama jobs con un UPDATE que filtra por `next_attempt_at <= <función_de_tiempo>`.

En PostgreSQL, `NOW()` devuelve la hora de **inicio de la transacción** (se congela al comienzo del bloque `BEGIN`). En los tests, DatabaseCleaner envuelve cada ejemplo en una transacción larga que se inicia **antes** de que los factories inserten los registros. Esto provoca que `next_attempt_at` (calculado con `Time.current` dentro del factory) sea mayor que `NOW()` (el instante en que la transacción de limpieza comenzó), haciendo que el WHERE `next_attempt_at <= NOW()` falle y el worker no encuentre ningún job.

Síntoma observado durante desarrollo:

```
next_attempt_at: 13:28:19.054
NOW():           13:28:18.969   ← inicio de transacción de DatabaseCleaner
→ cláusula WHERE devuelve 0 filas
```

## Decisión

Usar `CLOCK_TIMESTAMP()` en todos los lugares donde `CLAIM_SQL` necesita comparar o registrar instantes de tiempo reales:

```sql
UPDATE dispatch_queue
SET status = 'in_flight',
    locked_at   = CLOCK_TIMESTAMP(),
    updated_at  = CLOCK_TIMESTAMP()
WHERE id IN (
  SELECT id FROM dispatch_queue
  WHERE status = 'pending'
    AND next_attempt_at <= CLOCK_TIMESTAMP()
  ...
  FOR UPDATE SKIP LOCKED
)
```

`CLOCK_TIMESTAMP()` es equivalente de PostgreSQL al reloj de pared ("wall-clock time") y **no se congela** con el contexto de la transacción.

## Alternativas consideradas

| Alternativa | Problema |
|---|---|
| `NOW()` (default) | Congelada al inicio de la transacción; falla dentro de DatabaseCleaner |
| `CURRENT_TIMESTAMP` | Alias de `NOW()` — mismo problema |
| Pasar `Time.current` como parámetro Ruby | Funciona, pero añade round-trip Ruby↔DB y serialización de zona horaria |
| Cambiar DatabaseCleaner a truncation | Muy lento (reinicia tablas); rompería el aislamiento de otros tests |

## Consecuencias

- `CLAIM_SQL` usa `CLOCK_TIMESTAMP()` en SET y WHERE → los timestamps del row reflejan el instante real de la operación.
- Aplicar el mismo criterio a cualquier query raw en este módulo que requiera "hora actual" dentro de una transacción larga.
- No impacta producción (en producción no hay wrapping de transacción de test), solo resuelve el problema de testing.
