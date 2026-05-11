# Bench Results — 001-foundational-api

**Fecha**: 2026-05-10  
**Entorno**: desarrollo local (Docker Postgres 17-alpine, Ruby 3.3, Rails 8.1)  
**Hardware**: Linux 6.17, x86_64

## Configuración

```
rake bench:ingestion[140,60]
```

- Target: 140 rps sostenidos × 60 segundos
- Hilos: 32 workers + 1 producer
- Pool de conexiones: 36
- Estrategia de carga: rate-limited con queue de tokens (10ms interval)
- Notification class: `bench_ingestion` (cada invocación con `context_id` único → 0 duplicados)

## Resultados

| Métrica | Valor | Objetivo | Estado |
|---------|-------|----------|--------|
| Throughput sostenido | 140.0 rps | ~140 rps | ✅ |
| Latencia p50 | 4.89 ms | — | — |
| Latencia p95 | 7.52 ms | < 50 ms | ✅ |
| Latencia p99 | 9.01 ms | — | — |
| Errores | 0 | 0 | ✅ |
| Filas procesadas | 8.400 | 8.400 | ✅ |
| Duración real | 60.0 s | 60 s | ✅ |

## Notas

- p95 muy por debajo del objetivo (7.5 ms vs 50 ms): el cuello de botella a esta escala es la latencia de red al Docker Postgres, no la lógica de ingesta.
- El rate-limiter usa un producer thread que despacha batches de 10ms para mantener el RPS objetivo sin generar thundering herd.
- Los resultados en producción dependen de la latencia real al servidor Postgres y del número de workers disponibles.
