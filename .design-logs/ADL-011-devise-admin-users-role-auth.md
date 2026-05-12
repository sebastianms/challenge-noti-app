# ADL-011 — Devise + admin_users(role) para el panel admin (Phase 7)

**Fecha**: 2026-05-12
**Estado**: Aceptado
**Feature**: [006-admin-dashboard-rules](../specs/006-admin-dashboard-rules/)

---

## Contexto

Phase 7 introduce la primera UI operativa del panel admin. Fases anteriores (3–6) protegían los endpoints `/admin/*` con HTTP Basic Auth via ENV vars (`AUDIT_BASIC_AUTH_USER` / `AUDIT_BASIC_AUTH_PASSWORD`). Al agregar roles diferenciados y sesiones persistentes, HTTP Basic ya no es suficiente.

---

## Decisión

Usar **Devise 4.9** con una tabla `admin_users` separada (no `users`), con columna `role` (`CHECK` en PostgreSQL) y los módulos:
- `Database Authenticatable` — credenciales propias, no OAuth/SSO externo.
- `Lockable` — bloqueo tras 5 intentos fallidos, desbloqueo en 10 min.
- `Trackable` — last sign in IP/time, útil para auditoría básica.
- `Rememberable`, `Validatable`.

Los roles (`admin`, `product`, `support`, `engineering`) se gestionan con `Admin::RoleAuthorizer::PERMISSIONS` — un hash estático que mapea secciones a roles permitidos. `BaseController#authorize_section!` evalúa cada request.

---

## Alternativas consideradas

| Opción | Pros | Contras | Descartada porque |
|--------|------|---------|-------------------|
| HTTP Basic + ENV | Cero dependencias nuevas, simple | Sin roles, sin sesión, credenciales globales | No escala a 4 roles con permisos distintos |
| Pundit/CanCanCan | Políticas explícitas y testeables | Overhead de gema extra + boilerplate para 3 secciones | Overkill: PERMISSIONS hash resuelve el caso con < 20 líneas |
| JWT + SPA | Sin sesiones de servidor, escalable | Requiere frontend separado, complejidad de refresh tokens | Fuera del stack Rails-rendered acordado en `tech-stack.md` |
| OmniAuth/SSO | Sin gestión de passwords | Requiere proveedor externo (Google, Okta) | No disponible en entorno demo/challenge |

---

## Consecuencias

**Positivas**:
- Sesiones seguras con CSRF protection nativa de Rails.
- Lockable protege contra brute-force sin infraestructura adicional.
- `paranoid: true` evita enumerar usuarios válidos.
- Separación clara `admin_users` / `users` — sin riesgo de mezclar permisos de negocio con acceso operativo.

**Negativas / Trade-offs**:
- Password mínimo 12 chars — puede generar fricción en demos; mitigado con seeds predefinidos.
- Sin recuperación de password real (sin SMTP en dev) — aceptable para entorno demo.
- Roles hardcodeados en código — requiere redeploy para cambiar permisos de sección. Justificado: la granularidad de permisos no cambia en el ciclo de vida del producto.

---

## Referencias

- [Research R1/R2](../specs/006-admin-dashboard-rules/research.md) — análisis de opciones de autenticación.
- [tasks.md T006–T015](../specs/006-admin-dashboard-rules/tasks.md) — implementación Devise + BaseController.
- `app/policies/admin/role_authorizer.rb` — PERMISSIONS hash.
- `app/controllers/admin/base_controller.rb` — `authorize_section!`.
