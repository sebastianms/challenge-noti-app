# Quickstart — Escenarios de validación 002-email-dispatch

Cada escenario es ejecutable desde `rails console` o como spec de integración.

---

## Escenario 1 — Happy path: envío exitoso end-to-end

```ruby
# Setup: WebMock activo, stub 202
stub_request(:post, "https://api.sendgrid.com/v3/mail/send").to_return(status: 202)

result = WelcomeNotification.send("ana@example.com", context: { name: "Ana" })

# Verificaciones
result.created?                        # => true
result.correlation_id                  # => "uuid-..."

job = DispatchQueue.last
job.status                             # => "done"
job.attempts                           # => 1

audits = NotificationAudit.where(correlation_id: result.correlation_id).order(:created_at)
audits.map(&:status)                   # => ["enqueued", "dispatched", "delivered"]
```

---

## Escenario 2 — Reintento exitoso en segundo intento

```ruby
call_count = 0
stub_request(:post, "https://api.sendgrid.com/v3/mail/send").to_return do
  call_count += 1
  call_count == 1 ? { status: 503 } : { status: 202 }
end

result = WelcomeNotification.send("bob@example.com", context: { name: "Bob" })
worker = Central::Broker::Worker.new
worker.process_batch   # primer intento → 503 → pending con attempts=1
worker.process_batch   # segundo intento → 202 → done

job = DispatchQueue.last
job.status             # => "done"
job.attempts           # => 2
```

---

## Escenario 3 — DLQ tras 3 fallos consecutivos

```ruby
stub_request(:post, "https://api.sendgrid.com/v3/mail/send").to_return(status: 503)

result = WelcomeNotification.send("carol@example.com", context: { name: "Carol" })
worker = Central::Broker::Worker.new

3.times { worker.process_batch }

job = DispatchQueue.last
job.status             # => "failed"
job.attempts           # => 3
job.failed_reason      # => "sendgrid_5xx: 503"

# Cuarto intento no ocurre (permanente)
worker.process_batch
DispatchQueue.last.attempts  # => 3 (sin cambio)
```

---

## Escenario 4 — Recipient sin email → DLQ inmediato (error permanente)

```ruby
# user_id sin @
result = WelcomeNotification.send("user_42", context: { name: "Dave" })
result.created?   # => true (la ingesta acepta cualquier recipient válido)

worker = Central::Broker::Worker.new
worker.process_batch

job = DispatchQueue.last
job.status         # => "failed"
job.attempts       # => 1
job.failed_reason  # => "no_email_address"
# No hubo llamada a Sendgrid
assert_not_requested :post, "https://api.sendgrid.com/v3/mail/send"
```

---

## Escenario 5 — Duplicate no genera job en dispatch_queue

```ruby
r1 = WelcomeNotification.send("eve@example.com", context: { name: "Eve" })
r2 = WelcomeNotification.send("eve@example.com", context: { name: "Eve" })

r1.created?    # => true
r2.duplicate?  # => true

DispatchQueue.count  # => 1 (solo el primer evento genera job)
```

---

## Escenario 6 — X-Correlation-ID propagado a Sendgrid

```ruby
stub = stub_request(:post, "https://api.sendgrid.com/v3/mail/send").to_return(status: 202)

result = WelcomeNotification.send("frank@example.com", context: { name: "Frank" })
Central::Broker::Worker.new.process_batch

expect(stub).to have_been_requested.with(
  headers: { "X-Correlation-ID" => result.correlation_id }
)
```

---

## Escenario 7 — Agregar LogChannel sin tocar AbstractNotification

```ruby
# Registrar un canal nuevo en un initializer o spec:
log_channel = Class.new(Central::Channels::ChannelStrategy) do
  def deliver(event, recipient_id) = :delivered
  def channel_name                 = "log"
end
Central::Channels::ChannelRegistry.register(:log, log_channel.new)

# Verificar que el registry lo conoce
Central::Channels::ChannelRegistry.for(:log)  # => instancia de log_channel
# AbstractNotification y EventBuilder no fueron modificados
```
