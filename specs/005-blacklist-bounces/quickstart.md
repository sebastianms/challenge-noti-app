# Quickstart — 005-blacklist-bounces

Escenarios de validación end-to-end. Cubren los 3 user stories de la spec.

## Setup mínimo

```bash
bin/rails db:migrate
NotificationBlacklist.destroy_all   # estado limpio
NotificationAudit.delete_all
NotificationEvent.delete_all
```

## Escenario 1 — US1: opt-out manual desde consola (P1)

```ruby
NotificationBlacklist.create!(
  recipient_canonical: "blocked@example.com",
  scope:               "global",
  target:              nil,
  source:              "manual",
  reason:              "user requested unsubscribe via support ticket #42"
)

result = BirthdayNotification.send("Blocked@Example.com")  # casing distinto
result.filtered?  # => true
result.reason     # => "blacklisted"

NotificationAudit.where(recipient_canonical: "blocked@example.com").pluck(:status, :metadata).first
# => ["filtered", {"reason" => "blacklisted", "blacklist_id" => 1, "scope" => "global", "target" => nil}]

DispatchQueue.where(recipient_id: "blocked@example.com").count
# => 0   # no se encoló
```

**Esperado**: filtered, audit registrado, queue vacía.

## Escenario 2 — US2: auto-blacklist por hard bounce (P1)

```ruby
# Simular webhook con evento bounce duro
payload = [{
  email: "fail@example.com",
  event: "bounce",
  type:  "bounce",         # ← hard
  reason: "550 5.1.1 mailbox does not exist",
  sg_event_id: "evt_abc123",
  custom_args: { correlation_id: "uuid-xxx" }
}].to_json

post "/webhooks/sendgrid",
     params:  payload,
     headers: signed_headers(payload)   # helper de spec/support

# Procesar pendientes
WebhookEventWorker.new.process_batch

NotificationBlacklist.where(recipient_canonical: "fail@example.com").first
# => #<NotificationBlacklist scope="channel", target="email", source="hard_bounce", reason="550 5.1.1 ... (sg_event_id=evt_abc123)">

# Segundo intento de envío bloqueado
result = WelcomeNotification.send("fail@example.com")
result.filtered?  # => true
```

**Esperado**: ≤ 30 s desde POST webhook hasta blacklist visible. Siguientes envíos por email filtrados.

## Escenario 3 — US2.4: soft bounce NO blacklistea

```ruby
payload = [{
  email: "temporary@example.com",
  event: "bounce",
  type:  "blocked",        # ← soft (mailbox full, spam filter)
  reason: "421 4.2.1 try again later"
}].to_json

post "/webhooks/sendgrid", params: payload, headers: signed_headers(payload)
WebhookEventWorker.new.process_batch

NotificationBlacklist.where(recipient_canonical: "temporary@example.com").count
# => 0   # ← no blacklisted

NotificationAudit.where(recipient_canonical: "temporary@example.com", status: "bounced").count
# => 1   # ← audit normal sí
```

**Esperado**: solo audit; blacklist intacta.

## Escenario 4 — US3: remoción auditada desde UI

```ruby
entry = NotificationBlacklist.create!(
  recipient_canonical: "reactivated@example.com",
  scope: "global", source: "manual", reason: "ticket #99"
)

# UI: POST /admin/blacklist/1?_method=delete  body: reason="user reactivated account"
delete "/admin/blacklist/#{entry.id}",
       params: { reason: "user reactivated account" },
       headers: basic_auth_headers

NotificationBlacklist.find_by(id: entry.id)  # => nil

audit = NotificationAudit.where(notification_type: "_blacklist_removed_").last
audit.metadata["removed_by"]    # => "admin"  (HTTP Basic user)
audit.metadata["reason"]        # => "user reactivated account"
audit.metadata["blacklist_id"]  # => 1
```

**Esperado**: fila borrada, audit `blacklist_removed` con trazabilidad de quién/por qué.

## Escenario 5 — scope=type independiente entre tipos

```ruby
NotificationBlacklist.create!(
  recipient_canonical: "selective@example.com",
  scope: "type", target: "marketing", source: "manual", reason: "no marketing"
)

MarketingNotification.send("selective@example.com").filtered?  # => true
MfaNotification.send("selective@example.com").filtered?        # => false (otro tipo)
MfaNotification.send("selective@example.com").created?         # => true
```

**Esperado**: solo el tipo bloqueado se filtra; otros tipos pasan.

## Smoke benchmark (SC-005)

```ruby
# Crear 100k filas dummy de blacklist
100_000.times.map { |i| { recipient_canonical: "user#{i}@x.com", scope: "global", source: "manual", created_at: Time.current } }
  .each_slice(1000) { |batch| NotificationBlacklist.insert_all(batch) }

# Medir p95 de evaluator sobre 1000 lookups
times = 1000.times.map do
  Benchmark.realtime do
    BlacklistEvaluator.match(event: OpenStruct.new(recipient_canonical: "user#{rand(100_000)}@x.com", notification_type: "birthday"))
  end * 1000  # ms
end

p95 = times.sort[(times.size * 0.95).to_i]
puts "p95 = #{p95.round(2)} ms"   # esperado ≤ 5 ms
```
