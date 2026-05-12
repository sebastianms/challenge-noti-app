# Runbook operativo — Central de Notificaciones

**Audiencia**: Ingeniería de guardia / SRE  
**Actualizado**: 2026-05-12

---

## (a) DLQ saturada

### Síntomas

- Métrica `noti_dlq_size` supera el umbral de alerta (> 100 entradas).
- El dashboard muestra un conteo creciente en la sección "DLQ / Cola fallida".
- Los logs del worker contienen `status: failed` repetido para el mismo `event_id`.

### Diagnóstico

```bash
# Ver las entradas más recientes en la DLQ con su razón de fallo
docker compose exec app bin/rails console
```

```ruby
DispatchQueue.where(status: "failed")
             .order(updated_at: :desc)
             .limit(20)
             .pluck(:event_id, :attempts, :failed_reason, :updated_at)
```

Clasifica los errores:

```ruby
# Frecuencia por clase de error
DispatchQueue.where(status: "failed")
             .group("split_part(COALESCE(failed_reason, ''), ':', 1)")
             .count
```

### Remediación

**Caso 1 — Error transitorio (red, timeout SendGrid):**

```bash
# Re-encolar todas las entradas fallidas (las reintenta el worker)
docker compose exec app bin/rails console
```

```ruby
DispatchQueue.where(status: "failed").update_all(
  status: "pending",
  attempts: 0,
  next_attempt_at: Time.current,
  failed_reason: nil
)
```

**Caso 2 — Error permanente (destinatario inválido, plantilla rota):**

1. Identifica el `notification_type` afectado por `event_id`.
2. Corrige la causa raíz (template, validación del destinatario).
3. Descarta las entradas que ya no se pueden recuperar desde el panel `/admin/dlq` (botón Discard) o via consola:

```ruby
DispatchQueue.where(status: "failed", event_id: [id1, id2]).update_all(status: "discarded")
```

### Criterios de escalación

- Si más del 10 % de la cola total pasa a `failed` en < 5 minutos → escalar a ingeniería.
- Si el re-encolado no reduce el conteo en 15 minutos → investigar el worker con `docker compose logs worker`.

---

## (b) Bounce rate alto

### Síntomas

- Métrica `noti_bounce_rate_5m` supera 0.05 (5 % en ventana de 5 min).
- SendGrid reporta bounces en su dashboard de actividad.
- `NotificationAudit` acumula filas con `status: bounced`.

### Diagnóstico

```bash
docker compose exec app bin/rails console
```

```ruby
# Últimos bounces con detalle
NotificationAudit.where(status: "bounced", source: "sendgrid_webhook")
                 .order(created_at: :desc)
                 .limit(20)
                 .pluck(:correlation_id, :payload, :created_at)
```

```ruby
# Distribución por dominio del destinatario
NotificationAudit.where(status: "bounced")
                 .where("created_at >= ?", 1.hour.ago)
                 .pluck("payload->>'email'")
                 .map { |e| e.to_s.split("@").last }
                 .tally
                 .sort_by { |_, v| -v }
```

### Remediación

**Caso 1 — Bounces en un solo dominio:**
- El dominio puede haber bloqueado el IP de SendGrid o expirado los MX records.
- Agrega el dominio a la blacklist temporalmente: `/admin/blacklist`.
- Abre un ticket con SendGrid para investigar la reputación del IP.

**Caso 2 — Bounces distribuidos (spike generalizado):**
- Probablemente un lote de correos inválidos ingresó al sistema.
- Identifica el `notification_type` asociado y suspende temporalmente los envíos de ese tipo con una regla de throttle a 0 desde `/admin/rules`.
- Limpia los destinatarios inválidos en el origen de datos del caller.

**Caso 3 — Falso positivo (webhook procesado dos veces):**
- Revisa duplicados en `WebhookEvent` con mismo `sendgrid_event_id`.

### Criterios de escalación

- Bounce rate > 10 % sostenido por > 10 min → escalar. SendGrid puede suspender la cuenta si supera su umbral de reputación (5 %).

---

## (c) SendGrid caído

### Síntomas

- `DispatchQueue` acumula filas `in_flight` o `failed` con `failed_reason` que contiene `SendGrid` / `Net::HTTP` / timeout.
- Los workers completan sus intentos rápido (timeouts cortos) y llenan la DLQ.
- No llegan correos a destinatarios.

### Diagnóstico

```bash
# Verificar el estado del servicio en https://status.sendgrid.com
# O testear conectividad directa:
docker compose exec app curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $SENDGRID_API_KEY" \
  https://api.sendgrid.com/v3/scopes
# → 200 si está operativo
```

```ruby
# Ver tasa de fallos recientes del canal email
DispatchQueue.where(status: %w[failed in_flight])
             .where("updated_at >= ?", 30.minutes.ago)
             .count
```

### Remediación

1. **Confirmar la incidencia** en `https://status.sendgrid.com`.
2. **Pausar el worker** para evitar llenar la DLQ con reintentos inútiles:

```bash
docker compose stop worker
```

3. Durante la caída, los eventos quedan en `pending`/`failed` en la cola — se reintentarán automáticamente cuando el worker se relance.

4. Una vez que SendGrid restaure el servicio:

```bash
# Re-encolar los fallidos durante la ventana de caída
docker compose exec app bin/rails console
```

```ruby
DispatchQueue.where(status: "failed")
             .where("updated_at >= ?", 2.hours.ago)
             .update_all(status: "pending", attempts: 0, next_attempt_at: Time.current)
```

```bash
docker compose start worker
```

5. Monitorear que `noti_queue_depth` decrece en los siguientes 10 minutos.

### Criterios de escalación

- Si la caída supera 2 horas → evaluar canal alternativo (SMTP directo vía `Net::SMTP`).
- Si el re-encolado no procesa en 30 min tras restaurar SendGrid → escalar a ingeniería.

---

## (d) Partición de auditoría faltante

### Síntomas

- Rails lanza `PG::CheckViolation` o `ActiveRecord::StatementInvalid` al insertar en `notification_audit`.
- Error típico: `no partition of relation "notification_audit" found for row`.
- Los registros de auditoría dejan de crearse para el mes nuevo.

### Diagnóstico

```bash
docker compose exec app bin/rails console
```

```ruby
# Ver qué particiones existen actualmente
ActiveRecord::Base.connection.execute(<<~SQL).to_a
  SELECT inhrelid::regclass AS partition_name
  FROM   pg_inherits
  WHERE  inhparent = 'notification_audit'::regclass
  ORDER  BY partition_name;
SQL
```

Si la partición del mes siguiente no aparece, el problema es que no se creó preventivamente.

### Remediación

Crea la partición para el mes faltante (ejemplo: junio 2026):

```bash
docker compose exec app bin/rails console
```

```ruby
ActiveRecord::Base.connection.execute(<<~SQL)
  CREATE TABLE IF NOT EXISTS notification_audit_2026_06
    PARTITION OF notification_audit
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
SQL
```

Verifica que la partición quedó correctamente:

```ruby
ActiveRecord::Base.connection.execute(<<~SQL).to_a
  SELECT inhrelid::regclass FROM pg_inherits
  WHERE inhparent = 'notification_audit'::regclass
  ORDER BY 1;
SQL
```

**Automatización recomendada**: crear un job mensual (Rake task o cron) que cree la partición del mes siguiente con al menos 7 días de anticipación:

```ruby
# Ejemplo de task preventiva
next_month = Date.today.next_month.beginning_of_month
table_name = "notification_audit_#{next_month.strftime('%Y_%m')}"
from_val   = next_month.strftime("%Y-%m-01")
to_val     = next_month.next_month.strftime("%Y-%m-01")

ActiveRecord::Base.connection.execute(<<~SQL)
  CREATE TABLE IF NOT EXISTS #{table_name}
    PARTITION OF notification_audit
    FOR VALUES FROM ('#{from_val}') TO ('#{to_val}');
SQL
```

### Criterios de escalación

- Si la partición falta y ya hay datos del nuevo mes sin guardar → escalar inmediatamente. Los datos no se recuperan sin la partición activa.
- Si hay datos de auditoría del mes perdido en otra tabla/log → abrir incidencia de integridad de datos.

---

## (e) Alarmas recomendadas

Las siguientes métricas están expuestas en `/metrics` (formato Prometheus). Se recomienda configurar alertas en Grafana o en el sistema de monitoreo del equipo.

| Métrica | Umbral de alerta | Umbral crítico | Rationale |
|---------|-----------------|----------------|-----------|
| `noti_dlq_size` | > 50 | > 200 | 50 entradas indica un problema emergente; 200 puede saturar la capacidad de reintentos del worker. |
| `noti_queue_depth` | > 500 | > 2000 | Una cola creciente sin reducción indica que el worker no alcanza el ritmo de ingesta (140 rps genera ~8400 eventos/min). |
| `noti_bounce_rate_5m` | > 0.03 (3 %) | > 0.08 (8 %) | SendGrid suspende cuentas con bounce rate sostenido > 5 %. La alerta a 3 % da margen de reacción. |
| `noti_webhook_lag_seconds` | > 300 (5 min) | > 900 (15 min) | Los webhooks de SendGrid deben procesarse en segundos; lag > 5 min indica que el worker está saturado o caído. |
| `noti_events_ingested_24h` | < 100 (mínimo esperado) | < 10 | Una caída brusca en ingesta indica un problema en el caller o en el endpoint `/internal/ingest`. |
| `noti_dispatch_errors_by_class{class="Net::ReadTimeout"}` | > 10/5min | > 50/5min | Errores de timeout de red apuntan a degradación de SendGrid o del canal de red. |

### Configuración mínima sugerida (Prometheus alerting rule)

```yaml
groups:
  - name: noti_app
    rules:
      - alert: DLQSaturada
        expr: noti_dlq_size > 200
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "DLQ con {{ $value }} entradas fallidas"
          runbook: "docs/runbook.md#a-dlq-saturada"

      - alert: BounceRateAlto
        expr: noti_bounce_rate_5m > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Bounce rate en {{ $value | humanizePercentage }}"
          runbook: "docs/runbook.md#b-bounce-rate-alto"

      - alert: QueueDepthCritico
        expr: noti_queue_depth > 2000
        for: 3m
        labels:
          severity: critical
        annotations:
          summary: "Queue depth en {{ $value }} eventos"
          runbook: "docs/runbook.md#a-dlq-saturada"
```
