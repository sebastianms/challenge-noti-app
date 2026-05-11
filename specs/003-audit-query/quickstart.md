# Quickstart — Escenarios de validación 003-audit-query

Cada escenario es ejecutable desde `rails console` o como spec de integración.

---

## Escenario 1 — Búsqueda por correlation_id retorna timeline

```ruby
result = BirthdayNotification.send("juan@example.com", context: { name: "Juan" })
Worker.process_batch
# ya hay 3 entradas en notification_audit: enqueued, dispatched, delivered (source=internal)

audits = AuditSearch.new(correlation_id: result.correlation_id).call
audits.map { |a| [a.status, a.source] }
# => [["enqueued", "internal"], ["dispatched", "internal"], ["delivered", "internal"]]
audits.first.recipient_canonical  # => "juan@example.com"
```

---

## Escenario 2 — Filtros combinados con paginación

```ruby
# Crear 60 envíos fallidos a distintos destinatarios en el mes
60.times { |i| BirthdayNotification.send("user_#{i}@example.com") }
stub_sendgrid_error(status: 503)
3.times { Worker.process_batch; DispatchQueue.update_all(next_attempt_at: 1.minute.ago) }

results = AuditSearch.new(
  status:   "failed",
  from:     Date.new(2026, 5, 1),
  to:       Date.new(2026, 5, 31),
  page:     1,
  per_page: 50
).call

results.items.size  # => 50 (capped)
results.total       # => 60
results.has_next?   # => true
```

---

## Escenario 3 — Webhook de SendGrid se persiste async

```ruby
payload = [
  {
    email: "juan@example.com",
    timestamp: 1715472000,
    event: "delivered",
    custom_args: { correlation_id: "uuid-abc-123" }
  }
].to_json

signature, ts = sign_with_sendgrid_test_key(payload)

post "/webhooks/sendgrid",
  params:  payload,
  headers: {
    "Content-Type"                                    => "application/json",
    "X-Twilio-Email-Event-Webhook-Signature"          => signature,
    "X-Twilio-Email-Event-Webhook-Timestamp"          => ts
  }

# Respuesta inmediata
expect(response.status).to eq(200)

# Antes del worker, audit_count no cambió
expect(NotificationAudit.where(source: "sendgrid_webhook").count).to eq(0)
expect(WebhookEvent.where(status: "pending").count).to eq(1)

# Tras el worker
WebhookEventWorker.process_batch
expect(WebhookEvent.where(status: "processed").count).to eq(1)
expect(NotificationAudit.where(source: "sendgrid_webhook", correlation_id: "uuid-abc-123").count).to eq(1)
```

---

## Escenario 4 — Webhook con firma inválida rechazado

```ruby
post "/webhooks/sendgrid",
  params: "[]",
  headers: {
    "Content-Type"                                    => "application/json",
    "X-Twilio-Email-Event-Webhook-Signature"          => "invalid==",
    "X-Twilio-Email-Event-Webhook-Timestamp"          => "1715472000"
  }

expect(response.status).to eq(401)
expect(WebhookEvent.count).to eq(0)
```

---

## Escenario 5 — Webhook con bounce hard registra el tipo

```ruby
payload = [{
  email: "bouncer@example.com",
  event: "bounce",
  type:  "hard",
  reason: "550 user unknown",
  custom_args: { correlation_id: "uuid-bounce-1" }
}].to_json

post_signed_webhook(payload)
WebhookEventWorker.process_batch

audit = NotificationAudit.find_by(correlation_id: "uuid-bounce-1")
audit.status                  # => "bounced"
audit.source                  # => "sendgrid_webhook"
audit.metadata["type"]        # => "hard"
audit.recipient_canonical     # => "bouncer@example.com"
```

---

## Escenario 6 — PartitionManager crea siguiente, dropea antiguas, respeta safety

```ruby
# Setup: hoy es 2026-05-11, retención configurada en 6 meses
PartitionManager.new(table: "notification_audit", retention_months: 6).rotate

# Verifica:
# - notification_audit_2026_06 ahora existe (creada)
# - notification_audit_2025_11 fue dropeada (>6 meses)
# - notification_audit_2026_03 NO fue dropeada (< 3 meses, safety guardrail)

# Idempotencia:
expect { PartitionManager.new(table: "notification_audit", retention_months: 6).rotate }
  .not_to raise_error
```

---

## Escenario 7 — Búsqueda por destinatario combina entradas internal + sendgrid_webhook

```ruby
# Envío normal + webhook delivered del mismo correlation_id
result = BirthdayNotification.send("ana@example.com", context: { name: "Ana" })
Worker.process_batch
post_signed_webhook([{
  email: "ana@example.com",
  event: "delivered",
  custom_args: { correlation_id: result.correlation_id }
}].to_json)
WebhookEventWorker.process_batch

audits = AuditSearch.new(recipient: "ana@example.com").call
audits.items.map(&:source).uniq.sort
# => ["internal", "sendgrid_webhook"]
audits.items.map(&:status)
# => ["enqueued", "dispatched", "delivered", "delivered"]
```

---

## Escenario 8 — Endpoint Hotwire requiere HTTP Basic

```ruby
get "/admin/audits"
expect(response.status).to eq(401)

get "/admin/audits", headers: { "Authorization" => basic_auth_header(ENV["AUDIT_BASIC_AUTH_USER"], ENV["AUDIT_BASIC_AUTH_PASSWORD"]) }
expect(response.status).to eq(200)
expect(response.body).to include("Auditoría")
```
