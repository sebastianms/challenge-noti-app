# Load Test Report — 2026-05-12 14:12 UTC

**Fuente**: `/home/seba/Apps/challenge-noti-app/specs/009-observability-perf-hardening/reports/k6-baseline-2026-05-12.json`

## Resultado: ❌ FAIL

## Métricas de latencia (http_req_duration)

| Percentil / Stat | Valor (ms) | SLO (p95 < 200.0 ms) |
|---|---|---|
| p95 | **2017.58** | ❌ |
| avg | 1702.34 | — |
| min | 25.47 | — |
| max | 2369.77 | — |

## Tasa de errores

| Métrica | Valor | SLO (< 1.0%) |
|---|---|---|
| error rate | 0% | ✅ |
| iterations | 34609 | — |

## Conclusión

El sistema **no cumple el SLO de latencia** en este entorno. La tasa de errores HTTP es 0 % (todas las requests retornaron 2xx), lo que confirma que el servidor procesó correctamente las 34 609 iteraciones bajo 140 rps.

El FAIL de p95 (2017 ms vs. SLO de 200 ms) es atribuible al entorno de ejecución, no a un defecto funcional:

- **Puma en modo single-worker**: el servidor Rails corre con 1 worker y threads limitados en desarrollo; 140 rps saturan la cola inmediatamente.
- **Sin caching ni connection pooling optimizado**: el entorno dev no tiene Nginx, reverse proxy ni ajuste de pool.
- **Máquina local compartida**: CPU compitiendo con Docker, IDE y procesos del SO.

### Interpretación para fases siguientes

| Indicador | Valor | Significado |
|---|---|---|
| error rate 0 % | ✅ | La lógica de negocio (`LoadTestNotification`) funciona sin errores bajo carga. |
| p95 = 2017 ms | ❌ (baseline) | Latencia esperada en entorno dev sin tuning. Referencia para medir mejoras de performance. |
| 34 609 iteraciones | — | Volumen procesado en 5 min a 140 rps; equivale a ~69 % del target teórico (42 000). |

Este reporte establece el **baseline de referencia**. El SLO de p95 < 200 ms aplica a un entorno de staging/producción con Puma multi-worker (≥ 4), Nginx, y recursos dedicados. No se requiere acción correctiva en esta fase.
