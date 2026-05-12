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

El sistema **no cumple** los SLOs. Revisar: p95 2017.58 ms supera límite 200.0 ms. 
