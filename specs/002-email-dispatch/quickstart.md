# Quickstart — Escenarios de validación 002-email-dispatch

Cada escenario es ejecutable desde `rails console` o como spec de integración.
Los escenarios 1, 5 y 6 están cubiertos por `spec/integration/email_dispatch_spec.rb`.

---

## Escenario 1 — Happy path: envío exitoso end-to-end

```ruby
# Setup: WebMock activo, stub 202
stub_request(:post, "https://api.sendgrid.com/v3/mail/send").to_return(status: 202)

result = BirthdayNotification.send("ana@example.com", context: { name: "Ana" })

# Verificaciones
result.created?                        # => true
result.correlation_id                  # => "uuid-..."

Worker.process_batch

job = DispatchQueue.last
job.status                             # => "done"

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

result = BirthdayNotification.send("bob@example.com", context: { name: "Bob" })

Worker.process_batch   # primer intento → 503 → pending con attempts=1
# Avanzar next_attempt_at al pasado para que el worker vuelva a reclamar el job:
DispatchQueue.last.update!(next_attempt_at: 1.minute.ago)
Worker.process_batch   # segundo intento → 202 → done

job = DispatchQueue.last
job.status             # => "done"
job.attempts           # => 1
```

---

## Escenario 3 — DLQ tras 3 fallos consecutivos

```ruby
stub_request(:post, "https://api.sendgrid.com/v3/mail/send").to_return(status: 503)

result = BirthdayNotification.send("carol@example.com", context: { name: "Carol" })

3.times do
  Worker.process_batch
  DispatchQueue.where(status: "pending").update_all(next_attempt_at: 1.minute.ago)
end

job = DispatchQueue.last
job.status             # => "failed"
job.attempts           # => 3
job.failed_reason      # => "sendgrid_5xx: 503"

# Cuarto intento no ocurre (job ya está failed)
Worker.process_batch
DispatchQueue.last.attempts  # => 3 (sin cambio)
```

---

## Escenario 4 — Recipient sin email → ArgumentError en EmailChannel

```ruby
# user_id sin @ es rechazado por EmailChannel antes de llamar a Sendgrid
result = BirthdayNotification.send("user_42", context: { name: "Dave" })
result.created?   # => true (la ingesta acepta cualquier recipient válido)

# El worker llama EmailChannel#deliver con "user_42" → ArgumentError → PermanentError
stub_request(:post, "https://api.sendgrid.com/v3/mail/send").to_return(status: 202)
Worker.process_batch

job = DispatchQueue.last
job.status         # => "failed"
job.failed_reason  # => incluye "recipient_id must be an email address"
# No hubo llamada a Sendgrid
assert_not_requested :post, "https://api.sendgrid.com/v3/mail/send"
```

---

## Escenario 5 — Duplicate no genera job en dispatch_queue

```ruby
freeze_time do
  r1 = BirthdayNotification.send("eve@example.com", context: { name: "Eve" })
  r2 = BirthdayNotification.send("eve@example.com", context: { name: "Eve" })

  r1.created?    # => true
  r2.duplicate?  # => true

  DispatchQueue.count  # => 1 (solo el primer evento genera job)
end
```

---

## Escenario 6 — Correlation ID propagado a Sendgrid

El `correlation_id` viaja en dos lugares del request:
- **Header HTTP** `X-Correlation-ID` — para correlacionar logs de requests salientes.
- **`custom_args`** en el payload JSON — SendGrid los persiste y los incluye en webhooks de eventos (bounce, delivered, open), permitiendo cruzar eventos de SendGrid con `notification_audit`.

```ruby
stub_request(:post, "https://api.sendgrid.com/v3/mail/send").to_return(status: 202)

result = BirthdayNotification.send("frank@example.com", context: { name: "Frank" })
Worker.process_batch

# Header HTTP (logs de requests salientes)
expect(WebMock).to have_requested(:post, "https://api.sendgrid.com/v3/mail/send")
  .with(headers: { "X-Correlation-ID" => result.correlation_id })

# custom_args (persiste en SendGrid → aparece en webhooks de eventos)
expect(WebMock).to have_requested(:post, "https://api.sendgrid.com/v3/mail/send")
  .with(body: hash_including("custom_args" => { "correlation_id" => result.correlation_id }))
```

Cuando SendGrid envía un webhook de bounce o delivered, el payload incluye `correlation_id`, lo que permite buscar directamente en `notification_audit`:

```ruby
# En el webhook handler de SendGrid:
NotificationAudit.find_by(correlation_id: params[:correlation_id])
```

---

## Escenario 7 — Agregar un canal nuevo sin tocar AbstractNotification

```ruby
# Registrar un canal nuevo en un initializer o spec:
log_channel = Class.new(ChannelStrategy) do
  def deliver(event, recipient_id, correlation_id:) = :delivered
  def channel_name = "log"
end
ChannelRegistry.register(:log, log_channel.new)

# Verificar que el registry lo conoce
ChannelRegistry.for(:log)  # => instancia de log_channel
# AbstractNotification y EventBuilder no fueron modificados
```
