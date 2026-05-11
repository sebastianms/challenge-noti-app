# Data Model — 006-admin-dashboard-rules

## Entidades nuevas

### `admin_users`

Operador con acceso al panel admin. Manejado por Devise.

| Columna | Tipo | Constraints | Notas |
|---|---|---|---|
| `id` | bigserial | PK | |
| `email` | citext | NOT NULL, UNIQUE | índice UNIQUE case-insensitive |
| `encrypted_password` | string | NOT NULL, default "" | Devise (bcrypt) |
| `role` | string | NOT NULL, CHECK IN (`admin`, `product`, `support`, `engineering`) | |
| `reset_password_token` | string | UNIQUE, NULL | Devise recoverable |
| `reset_password_sent_at` | timestamptz | NULL | |
| `remember_created_at` | timestamptz | NULL | |
| `sign_in_count` | integer | NOT NULL, default 0 | Devise trackable |
| `current_sign_in_at` | timestamptz | NULL | |
| `last_sign_in_at` | timestamptz | NULL | |
| `current_sign_in_ip` | inet | NULL | |
| `last_sign_in_ip` | inet | NULL | |
| `failed_attempts` | integer | NOT NULL, default 0 | Devise lockable |
| `unlock_token` | string | UNIQUE, NULL | |
| `locked_at` | timestamptz | NULL | |
| `created_at`, `updated_at` | timestamptz | NOT NULL | |

**Índices**:
- `UNIQUE (email)`
- `UNIQUE (reset_password_token)` WHERE NOT NULL
- `UNIQUE (unlock_token)` WHERE NOT NULL

**Reglas de validación (modelo)**:
- `email` formato + UNIQUE.
- `password` mínimo 12 caracteres (más estricto que Devise default 6, alineado al uso admin).
- `role` IN whitelist.

---

### `rule_changes`

Audit trail de operaciones CRUD sobre `notification_rules`.

| Columna | Tipo | Constraints | Notas |
|---|---|---|---|
| `id` | bigserial | PK | |
| `notification_rule_id` | bigint | FK → `notification_rules(id) ON DELETE SET NULL` | nullable para preservar histórico de borrados |
| `admin_user_id` | bigint | FK → `admin_users(id) ON DELETE RESTRICT`, NOT NULL | nunca borrar admins con historial |
| `action` | string | NOT NULL, CHECK IN (`created`, `updated`, `deleted`) | |
| `before` | jsonb | NULL | snapshot pre-cambio (null en `created`) |
| `after` | jsonb | NULL | snapshot post-cambio (null en `deleted`) |
| `changed_at` | timestamptz | NOT NULL, default `clock_timestamp()` | |

**Índices**:
- `(notification_rule_id, changed_at DESC)` — listado por regla
- `(admin_user_id, changed_at DESC)` — quién hizo qué
- `(changed_at DESC)` — feed global

**Invariantes**:
- `action = 'created'` ⇒ `before IS NULL AND after IS NOT NULL`
- `action = 'updated'` ⇒ `before IS NOT NULL AND after IS NOT NULL`
- `action = 'deleted'` ⇒ `before IS NOT NULL AND after IS NULL`

Validados en el modelo (no como CHECK DB para mantener flexibilidad de hot-fix).

---

## Entidades reusadas (sin cambios de esquema)

- `notification_rules` — usado por CRUD; sin alteraciones.
- `notification_audit` — fuente de KPIs.
- `dispatch_queue` — fuente de queue depth + DLQ size.
- `notification_blacklist` — sembrado por MockDataGenerator.

## Migraciones (orden)

1. `devise_create_admin_users` — generada por `rails g devise:install` + `rails g devise admin_user role:string`.
2. `add_role_check_to_admin_users` — añade CHECK constraint sobre `role`.
3. `create_rule_changes` — tabla del audit trail.
