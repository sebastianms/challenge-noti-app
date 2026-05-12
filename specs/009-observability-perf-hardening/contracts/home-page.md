# Contract — GET /

## Endpoint

```
GET /
```

Público, sin autenticación.

## Response 200 OK

`Content-Type: text/html; charset=utf-8`

### Estructura visual (rendered)

```text
┌────────────────────────────────────────────────────────────┐
│ [Logo] Central de Notificaciones        [Ir al dashboard*] │
│                                          (* solo si admin) │
├────────────────────────────────────────────────────────────┤
│                                                            │
│   Hero                                                     │
│   ──────                                                   │
│   Plataforma de notificaciones multi-canal con motor de    │
│   reglas, idempotencia y auditoría completa.               │
│                                                            │
├────────────────────────────────────────────────────────────┤
│   ¿Cómo funciona?                                          │
│                                                            │
│   1. Ingesta     — los equipos invocan FooNotif.send(...)  │
│   2. Decisión    — reglas + blacklist deciden si despachar │
│   3. Despacho    — workers procesan la cola hacia Sendgrid │
│   4. Auditoría   — cada paso queda registrado y consultable│
│                                                            │
├────────────────────────────────────────────────────────────┤
│   Endpoints públicos                                       │
│                                                            │
│   • /admin/login        Panel administrativo               │
│   • /metrics            Métricas Prometheus (auth)         │
│   • /webhooks/sendgrid  Webhook receiver (POST, Ed25519)   │
│                                                            │
├────────────────────────────────────────────────────────────┤
│   Repositorio: github.com/.../challenge-noti-app           │
│   Docs: README.md · runbook.md                             │
└────────────────────────────────────────────────────────────┘
```

### Elementos requeridos

| Selector / contenido | Razón |
|---|---|
| `<h1>` con nombre del producto | SEO + a11y |
| Texto descriptivo `< 200 chars` | scan rápido |
| Lista numerada con 4 pasos del flujo | comprensión sin diagrama |
| Tabla / lista de endpoints públicos con paths | descubribilidad operacional |
| Link visible al repo | trazabilidad |
| CTA condicional: si `admin_user_signed_in?` → "Ir al dashboard"; si no → "Login admin" | UX según contexto |

### Layout

Hereda `application.html.erb` (no `admin.html.erb`). Header simple con logo + CTA. Sin sidebar.

## Tests requeridos

- Renderiza 200 sin sesión.
- Renderiza 200 con sesión admin (CTA cambia).
- Sin redirect a `/admin/login` (regressión: hoy `/` puede redirigir).
- Tiempo total de render < 100 ms (sin queries pesadas).
