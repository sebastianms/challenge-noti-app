# Quickstart — 006-admin-dashboard-rules

Escenarios clave de validación para verificar el feature end-to-end.

## Setup

```bash
docker compose exec app bin/rails db:migrate
docker compose exec app bin/rails runner '
  AdminUser.create!(email: "admin@example.com",   password: "Admin12345678", role: "admin")
  AdminUser.create!(email: "product@example.com", password: "Admin12345678", role: "product")
  AdminUser.create!(email: "support@example.com", password: "Admin12345678", role: "support")
'
```

## Escenario 1 — US1 (auth + roles)

1. Abrir `http://localhost:3000/admin/login`.
2. Login con `support@example.com`.
3. Esperado: redirige a `/admin/dashboard` y solo se ve el dashboard (sin link a "Reglas").
4. Intentar acceder directo a `/admin/rules` → 403 con "No tienes permisos para esta sección".
5. Logout → vuelve a `/admin/login`.

## Escenario 2 — US1 lockable

1. Hacer 5 logins fallidos con `support@example.com`.
2. En el 6º intento (incluso con password correcta), responde 423 / mensaje de cuenta bloqueada.

## Escenario 3 — US4 mock data (poblar UI vacía)

1. Login como `admin@example.com`.
2. Dashboard inicial muestra estado vacío en los 4 KPIs.
3. Click en "Generar Data Mock".
4. Esperado: redirige al dashboard con flash success y los 4 KPIs ahora muestran valores > 0; `/admin/rules` lista al menos 3 reglas.

## Escenario 4 — US4 feature flag off

1. Reiniciar con `ALLOW_MOCK_DATA_FEATURE=false`.
2. Login como admin → el botón "Generar Data Mock" NO aparece.
3. `curl -X POST -b cookie.txt http://localhost:3000/admin/mock_data` → 403.

## Escenario 5 — US2 (dashboard)

1. Tras escenario 3, refrescar dashboard.
2. Volumen muestra barras agrupadas por tipo/canal.
3. Tasa de filtrado muestra pie con motivos.
4. Queue depth/DLQ size son contadores en vivo (refrescar agrega nuevos si el worker está parado).
5. Error rate por canal muestra porcentaje calculado.

## Escenario 6 — US3 (CRUD reglas + history)

1. Login como `product@example.com`.
2. `/admin/rules` → click "Nueva regla".
3. Crear `notification_type=demo_phase7`, `channels=[email]`, `max_per_day=2`, `priority=standard`.
4. Esperado: aparece en lista; `/admin/rules/<id>/history` muestra 1 entrada `created`.
5. Editar regla cambiando `max_per_day` a 5.
6. Esperado: `/admin/rules/<id>/history` muestra 2 entradas; la nueva `updated` con diff `{max_per_day: 2 → 5}`.
7. Eliminar regla → flash success; `/admin/rules` ya no la lista; pero `/admin/rules/<id>/history` (404 sobre la regla) — en su lugar, el feed global `/admin/rule_changes` muestra la fila `deleted`.

## Escenario 7 — autorización cross-rol

| Usuario | `/admin/dashboard` | `/admin/rules` | `POST /admin/mock_data` |
|---|---|---|---|
| admin | 200 | 200 | 200 (si flag on) |
| product | 200 | 200 | 403 |
| engineering | 200 | 403 | 403 |
| support | 200 | 403 | 403 |

## Benchmark SC-002

```bash
bundle exec rake bench:dashboard_load
```

Espera < 2s con 10k filas en ventana 24h. Si falla, revisar índices `(status, created_at)` y `(notification_type, created_at)` en `notification_audit`.
