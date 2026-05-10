# Quickstart — Validación de 001-foundational-api

**Date**: 2026-05-10

Escenarios end-to-end que se ejecutarán durante y al final de la implementación. Cada escenario es independientemente verificable.

## Prerrequisitos

- Postgres local corriendo (`docker compose up postgres`).
- `bundle exec rails db:create db:migrate`.
- Suite RSpec en verde antes de empezar.

---

## Escenario 1 — DevEx: integrar una notificación nueva en < 15 min (US1, SC-001)

**Objetivo**: validar que un ingeniero puede crear y disparar una notificación nueva sin tocar nada fuera de su archivo.

**Pasos**:

1. Crear `app/notifications/birthday_notification.rb`:
   ```ruby
   class BirthdayNotification < AbstractNotification
     notification_type :birthday

     def self.title(context = {})
       "¡Feliz cumpleaños, #{context[:name]}!"
     end

     def self.body(context = {})
       "Hoy te deseamos un excelente día."
     end
   end
   ```

2. Desde `bin/rails console`:
   ```ruby
   result = BirthdayNotification.send("juan@example.com", context: { name: "Juan" })
   # => #<SendResult state=:created correlation_id="abc-...-...">
   ```

3. Verificar en Postgres:
   ```sql
   SELECT correlation_id, notification_type, recipient_canonical, context_id
   FROM notification_events
   WHERE correlation_id = 'abc-...-...';
   -- 1 fila, type='birthday', recipient='juan@example.com', context_id='no_context'
   ```

**Criterio de éxito**: el flujo completo (crear archivo → invocar → ver fila) toma < 15 minutos para alguien que nunca tocó la plataforma.

---

## Escenario 2 — Idempotencia bajo concurrencia (US2, SC-002, SC-005)

**Objetivo**: 10.000 invocaciones concurrentes del mismo `(recipient, type, context)` producen exactamente una fila.

**Pasos**:

```ruby
# spec/integration/idempotency_concurrency_spec.rb
RSpec.describe "Idempotencia bajo carga concurrente" do
  it "produce exactamente una fila bajo 10k invocaciones simultáneas" do
    threads = 50
    per_thread = 200

    workers = threads.times.map do
      Thread.new do
        per_thread.times do
          BirthdayNotification.send("juan@example.com", context: { invoice: 42 })
        end
      end
    end
    workers.each(&:join)

    rows = Central::NotificationEvent
      .where(notification_type: "birthday", recipient_canonical: "juan@example.com", context_id: "42")
      .count
    expect(rows).to eq(1)
  end
end
```

**Criterios de éxito**:
- Exactamente 1 fila en `notification_events` para esa combinación.
- 9.999 retornos `:duplicate`, todos con el `correlation_id` del original.
- Cero excepciones de violación de unicidad propagadas al llamador.

---

## Escenario 3 — Bordes de ventana (US2, edge case documentado)

**Objetivo**: validar el comportamiento esperado del borde de ventana (no un bug, sino un trade-off declarado).

**Pasos** (test con tiempo controlado):

```ruby
travel_to Time.utc(2026, 5, 10, 10, 23, 59) do
  BirthdayNotification.send("juan@x.com", context: { invoice: 42 })
end

travel_to Time.utc(2026, 5, 10, 10, 24, 1) do
  BirthdayNotification.send("juan@x.com", context: { invoice: 42 })
end

expect(NotificationEvent.where(notification_type: "birthday").count).to eq(2)
```

**Criterio de éxito**: 2 filas. Esto **NO es un bug**: confirma que el `window_ts` discrimina correctamente y que el comportamiento documentado en R-08 es el real.

---

## Escenario 4 — Trazabilidad: correlation_id consultable (US3, SC-004)

**Objetivo**: cada evento creado expone un `correlation_id` UUID consultable, y los duplicados retornan el del original.

**Pasos**:

```ruby
r1 = BirthdayNotification.send("juan@x.com", context: { invoice: 42 })
r2 = BirthdayNotification.send("juan@x.com", context: { invoice: 42 })

expect(r1.created?).to be true
expect(r2.duplicate?).to be true
expect(r1.correlation_id).to eq(r2.correlation_id)
expect(r1.correlation_id).to match(/\A[\da-f-]{36}\z/)
```

---

## Escenario 5 — Validaciones de input (US2, edge cases)

**Objetivo**: inputs inválidos retornan `:rejected`, no excepciones, y no persisten nada.

**Casos**:

```ruby
# Recipient vacío
r = BirthdayNotification.send("")
expect(r.rejected?).to be true
expect(r.reason).to match(/blank/)

# Recipient con saltos de línea
r = BirthdayNotification.send("juan\nattacker@x.com")
expect(r.rejected?).to be true

# Recipient demasiado largo
r = BirthdayNotification.send("a" * 321)
expect(r.rejected?).to be true

# Payload no serializable (objeto custom sin to_json)
r = BirthdayNotification.send("juan@x.com", context: { obj: BasicObject.new })
expect(r.rejected?).to be true

# Ningún caso anterior debe haber persistido nada
expect(NotificationEvent.count).to eq(0)
```

---

## Escenario 6 — Carga sostenida (SC-003)

**Objetivo**: 140 invocaciones/seg sostenidas durante 10 minutos con p95 < 50 ms.

**Herramienta**: script de benchmark (no parte de la suite RSpec; ejecutado a mano contra DB local).

```bash
bundle exec rake bench:ingestion[140,600]
```

**Salida esperada**:

```
Throughput sostenido: 140.3 rps
Latencia p50: 8.2 ms
Latencia p95: 31.4 ms       ← < 50 ms ✓
Latencia p99: 47.1 ms
Errores: 0
Filas creadas: 84.180
Duplicados: 0 (cada invocación con context_id distinto)
```

---

## Escenario 7 — Subclase mal definida falla loud (FR-004)

**Objetivo**: una subclase que omite `title` o `body` falla con un mensaje claro la primera vez que se la usa.

```ruby
class BrokenNotification < AbstractNotification
  # falta title y body
end

expect { BrokenNotification.send("a@b.com") }
  .to raise_error(NotImplementedError, /must implement self.title/)
```

---

## Definition of Done de la feature

Todos los escenarios pasan + cobertura ≥ 90% en módulos `app/notifications` y `app/central/ingestion` + RuboCop sin warnings + Brakeman sin findings + CI verde.
