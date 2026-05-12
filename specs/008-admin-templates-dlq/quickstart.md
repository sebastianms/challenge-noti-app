# Quickstart — 008-admin-templates-dlq

Escenarios de validación end-to-end que el integration spec debe cubrir.

## E1 — Override de template visible en envío real

1. `sign_in` como `admin`.
2. POST `/admin/templates` con `notification_type=birthday`, `title="Hoy es tu día {{name}} 🎉"`, `body="Te deseamos lo mejor."`.
3. Invocar `BirthdayNotification.send("juan@example.com", context: { name: "Juan" })`.
4. **Esperado**: `dispatch_queue.last.payload["title"] == "Hoy es tu día Juan 🎉"`.

## E2 — Preview con variable faltante

1. GET `/admin/templates/:id/edit`.
2. POST a `/admin/templates/:id/preview` con `title="Hola {{name}}, ID={{user_id}}"` y `context={name: "Ana"}`.
3. **Esperado**: cuerpo de respuesta incluye `"Hola Ana, ID="` y un warning `"variable user_id no resolvió"`.

## E3 — DLQ: reintento individual

1. Crear job con `status=dead`, `attempts=3`, `last_error="Net::OpenTimeout: ..."`.
2. `sign_in` como `engineering`.
3. POST `/admin/dlq/:id/retry`.
4. **Esperado**: job ahora `status=pending`, `attempts=0`, `available_at <= NOW()`. Existe audit `_dlq_retried_` con `metadata.retried_by == engineering.email`.

## E4 — DLQ: reintento masivo capeado

1. Crear 600 jobs `dead` con mismo `last_error_class=Net::OpenTimeout`.
2. POST `/admin/dlq/bulk_retry` con `reason=Net::OpenTimeout`.
3. **Esperado**: 500 jobs pasan a `pending`, 100 quedan `dead`. Audit `_dlq_bulk_retried_` con `metadata.count==500` y `metadata.reason_filter=="Net::OpenTimeout"`. Mensaje flash informa "500 de 600".

## E5 — DLQ: descarte con motivo

1. POST `/admin/dlq/:id/discard` con `reason="recipient inválido confirmado por equipo"`.
2. **Esperado**: job `status=discarded`. Audit `_dlq_discarded_` con `metadata.reason` y `metadata.discarded_by`.

## E6 — Gating de roles

| Ruta | admin | product | engineering | support |
|------|-------|---------|-------------|---------|
| `/admin/templates` (GET) | ✅ 200 | ✅ 200 | ❌ 403 | ❌ 403 |
| `/admin/templates` (POST) | ✅ 302 | ✅ 302 | ❌ 403 | ❌ 403 |
| `/admin/dlq` (GET) | ✅ 200 | ❌ 403 | ✅ 200 | ❌ 403 |
| `/admin/dlq/:id/retry` (POST) | ✅ 302 | ❌ 403 | ✅ 302 | ❌ 403 |

## E7 — Fallback sin override

1. No crear template para `birthday`.
2. Invocar `BirthdayNotification.send(...)`.
3. **Esperado**: payload usa el copy del archivo `app/notifications/birthday_notification.rb` (compatibilidad Phase 2).
