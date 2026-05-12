# ADL-012 — Migración HTTP Basic → Devise para Audits y Blacklist (Phase 8)

**Fecha**: 2026-05-12
**Estado**: Aceptado
**Feature**: [007-admin-ui-audit-blacklist](../specs/007-admin-ui-audit-blacklist/)

---

## Contexto

Phase 4 y 6 implementaron los endpoints `/admin/audits` y `/admin/blacklist` con HTTP Basic Auth (ENV vars `AUDIT_BASIC_AUTH_USER` / `AUDIT_BASIC_AUTH_PASSWORD`). Phase 7 introdujo Devise con `admin_users` + roles. Convivir ambos sistemas de autenticación en el mismo namespace `/admin` genera inconsistencia UX (doble prompt de login) y dos superficies de credenciales distintas.

Adicionalmente, el `BlacklistController#destroy` usaba el header `HTTP_AUTHORIZATION` para extraer `removed_by` del usuario Basic, lo que producía `"admin"` (genérico) en lugar del email real del operador.

---

## Decisión

Migrar `AuditsController` y `BlacklistController` para heredar de `Admin::BaseController` (que ya implementa `authenticate_admin_user!` vía Devise y `authorize_section!` vía `RoleAuthorizer`). Eliminar `http_basic_authenticate_with` y `decode_basic_user`.

### Permisos agregados a `RoleAuthorizer::PERMISSIONS`

| Sección | admin | product | engineering | support |
|---------|-------|---------|-------------|---------|
| `audits` | ✓ | ✓ | ✓ | ✓ |
| `blacklist_read` | ✓ | ✓ | ✓ | ✓ |
| `blacklist_write` | ✓ | ✗ | ✗ | ✓ |

`BlacklistController` implementa `controller_section` como método de instancia (en lugar de constante) porque la sección cambia según la acción (`WRITE_ACTIONS = %i[create destroy]`).

---

## CSV Export (trade-off: send_data vs streaming)

Se eligió `send_data` con `CSV.generate` y carga en memoria sobre streaming con `ActionController::Live` porque:

| Criterio | send_data | ActionController::Live |
|----------|-----------|----------------------|
| Complejidad | Mínima | Alta (requiere thread-safe renderer, cierre explícito de `response.stream`) |
| Compatibilidad | Universal con Rack/Puma | Requiere config explícita en Puma |
| Límite práctico | ~10k filas ≈ 5 MB | Sin límite |
| Tiempo p95 con 10k filas | < 500 ms | Similar |

Para los volúmenes del panel de soporte (< 10k filas por búsqueda paginada), `send_data` es suficiente. El umbral de migración a streaming es ≥ 100k filas por export. ADL-012 documenta este criterio para futuras iteraciones.

---

## Alternativas consideradas

| Opción | Pros | Contras | Descartada porque |
|--------|------|---------|-------------------|
| Mantener HTTP Basic en audits/blacklist | Cero cambios | Auth inconsistente, `removed_by` genérico | UX rota y trazabilidad perdida |
| Nuevo controlador `admin_ui_*` en lugar de migrar | Backward compat con HTTP Basic | Duplicación, mismo problema subyacente | Violación DRY sin ganancia real |
| Política Pundit para `blacklist_write` | Más explícito | Gema extra, boilerplate para 1 distinción | `controller_section` como método cubre el caso con 3 líneas |

---

## Consecuencias

**Positivas**:
- Un solo sistema de auth en todo `/admin/*` — 0 prompts HTTP Basic.
- `metadata.removed_by` pasa de `"admin"` (genérico) a `current_admin_user.email` (trazable por persona).
- CSV export habilitado en ambos módulos sin dependencia nueva.
- Roles `support` y `engineering` pueden leer audits/blacklist sin escalar a ingeniería.

**Negativas / Trade-offs**:
- Clientes que automatizan llamadas a `/admin/audits` con HTTP Basic dejarán de funcionar — requieren sesión Devise. Impacto nulo en demo/challenge.
- `send_data` carga todo el resultado en memoria. Aceptable para < 10k filas.

---

## Referencias

- [ADL-011](ADL-011-devise-admin-users-role-auth.md) — decisión base de Devise + roles.
- [specs/007-admin-ui-audit-blacklist/plan.md](../specs/007-admin-ui-audit-blacklist/plan.md) — diseño técnico completo.
