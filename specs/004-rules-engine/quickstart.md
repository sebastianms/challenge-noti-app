# Quickstart — 004-rules-engine

Escenarios de validación end-to-end. Cada uno debe pasar como spec de integración antes de cerrar la feature.

## Escenario 1 — Rate limit (US1)

```ruby
NotificationRule.create!(notification_type: "welcome", max_per_day: 1, channels: ["email"])

3.times { WelcomeNotification.send("juan@example.com", context: { name: "Juan" }) }

audits = NotificationAudit.where(recipient_canonical: "juan@example.com")
audits.where(status: "enqueued").count   # => 1
audits.where(status: "filtered").count   # => 2
audits.where(status: "filtered").first.metadata["reason"]  # => "rate_limited"
```

## Escenario 2 — Disabled channel (US1)

```ruby
NotificationRule.create!(notification_type: "marketing", channels: [])
MarketingNotification.send("user@example.com")

audit = NotificationAudit.last
audit.status                          # => "filtered"
audit.metadata["reason"]              # => "disabled"
DispatchQueue.count                   # => 0 (no se encoló)
```

## Escenario 3 — Default sin regla (compatibilidad)

```ruby
# No existe regla para "payment_failed"
PaymentFailedNotification.send("user@example.com", context: { amount: 100 })

# Comportamiento idéntico a Phase 3
DispatchQueue.count           # => 1
NotificationAudit.count       # => 1 (enqueued)
```

## Escenario 4 — Digest (US2)

```ruby
NotificationRule.create!(
  notification_type:     "mention",
  digest_window_seconds: 60,
  channels:              ["email"]
)

5.times { MentionNotification.send("alice@example.com", context: { from: "bob" }) }

PendingDigest.where(status: "pending").count  # => 5
DispatchQueue.count                           # => 0

travel 65.seconds
Central::Broker::DigestScheduler.process_batch

DispatchQueue.count                                       # => 1
PendingDigest.where(status: "consolidated").count         # => 5
NotificationAudit.where(status: "digested").count         # => 5
```

## Escenario 5 — Edición en caliente (US3)

```ruby
rule = NotificationRule.create!(notification_type: "welcome", max_per_day: 3)
3.times { WelcomeNotification.send("juan@example.com") }   # 3 dispatch ok

rule.update!(max_per_day: 1)
# El after_save invalida el cache → próxima evaluación lee BD

WelcomeNotification.send("juan@example.com")
NotificationAudit.where(status: "filtered").last.metadata["reason"]
# => "rate_limited"
```

## Escenario 6 — Auditoría con rule_id (US4)

```ruby
rule = NotificationRule.create!(notification_type: "welcome", max_per_day: 0)
# (Nota: en realidad max_per_day=0 no es válido por constraint; usamos channels=[])
rule.update_columns(max_per_day: nil, channels: [])
WelcomeNotification.send("juan@example.com")

audit = NotificationAudit.last
audit.metadata["rule_id"]  # => rule.id
audit.metadata["reason"]   # => "disabled"
```

## Escenario 7 — Cache hit rate (SC-002)

```ruby
NotificationRule.create!(notification_type: "welcome", channels: ["email"])

ActiveRecord::Base.connection.unprepared_statement do
  count = 0
  ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
    count += 1 if payload[:sql]&.include?("notification_rules")
  end

  100.times { WelcomeNotification.send("a#{_1}@example.com") }
  expect(count).to be <= 1   # 1 hit en cache miss inicial, resto cache hits
end
```

## Escenario 8 — Concurrencia del scheduler (FR-011)

```ruby
NotificationRule.create!(notification_type: "mention", digest_window_seconds: 60)
20.times { MentionNotification.send("alice@example.com") }
travel 65.seconds

threads = 4.times.map { Thread.new { DigestScheduler.process_batch(batch_size: 10) } }
threads.each(&:join)

# Ningún item se consolida dos veces
PendingDigest.where(status: "consolidated").count  # => 20
DispatchQueue.count                                 # => 1 (un solo digest por grupo)
```
