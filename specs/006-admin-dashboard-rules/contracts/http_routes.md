# HTTP contracts — 006-admin-dashboard-rules

Todas las rutas viven bajo `namespace :admin`. Auth = Devise (cookie de sesión); las acciones que devuelven 403 lo hacen vía `Admin::RoleAuthorizer`.

## Auth (Devise)

| Método | Path | Acción | Auth | Respuesta éxito | Errores |
|---|---|---|---|---|---|
| GET | `/admin/login` | `sessions#new` | público | 200 form | — |
| POST | `/admin/login` | `sessions#create` | público | 302 → `/admin/dashboard` | 200 form con mensaje genérico si credenciales inválidas; 423 (locked) tras 5 fallos |
| DELETE | `/admin/logout` | `sessions#destroy` | autenticado | 302 → `/admin/login` | — |

## Dashboard

| Método | Path | Acción | Roles permitidos | Respuesta éxito | Errores |
|---|---|---|---|---|---|
| GET | `/admin/dashboard` | `dashboard#index` | admin, product, engineering, support | 200 HTML con 4 KPIs | 401 si no autenticado |

**Payload de KPIs (renderizado server-side, no JSON público)**:
```
{
  volume_by_type_channel: { ["birthday", "email"] => 23, ... },
  filter_rate_by_reason:  { "blacklisted" => 5, "rate_limited" => 3, ... },
  queue_depth: 12,
  dlq_size:    3,
  error_rate_by_channel: { "email" => 0.04 }
}
```

## Rules (CRUD + history)

| Método | Path | Acción | Roles permitidos | Respuesta éxito | Errores |
|---|---|---|---|---|---|
| GET | `/admin/rules` | `rules#index` | admin, product | 200 listado | 403 support/engineering |
| GET | `/admin/rules/new` | `rules#new` | admin, product | 200 form | 403 |
| POST | `/admin/rules` | `rules#create` | admin, product | 302 → `/admin/rules` | 422 + form con errores |
| GET | `/admin/rules/:id/edit` | `rules#edit` | admin, product | 200 form | 403, 404 |
| PATCH/PUT | `/admin/rules/:id` | `rules#update` | admin, product | 302 → `/admin/rules` | 422 |
| DELETE | `/admin/rules/:id` | `rules#destroy` | admin, product | 303 → `/admin/rules` | 404 |
| GET | `/admin/rules/:id/history` | `rules#history` | admin, product | 200 lista de RuleChange | 403, 404 |

**Form params**: `notification_type`, `channels[]`, `max_per_day`, `cooldown_seconds`, `digest_window_seconds`, `priority`, `enabled` (checkbox).

## Mock Data

| Método | Path | Acción | Roles permitidos | Respuesta éxito | Errores |
|---|---|---|---|---|---|
| POST | `/admin/mock_data` | `mock_data#create` | admin (sólo) | 303 → referrer con flash success "Mock data generated" | 403 si `ALLOW_MOCK_DATA_FEATURE=false`; 403 si rol ≠ admin |

**Sin body**. Idempotente sobre reglas y blacklist; acumulativo sobre audits/queue.

## Errores comunes

- 401 unauthenticated: redirige a `/admin/login` con flash.
- 403 forbidden: renderiza `errors/forbidden.html.erb`.
- 422: form re-render con errores inline.
- 404: `errors/not_found.html.erb`.
