# Contract: `POST /webhooks/sendgrid`

## Request

**Method**: `POST`
**Path**: `/webhooks/sendgrid`
**Content-Type**: `application/json`

### Headers requeridos

| Header | Valor | Origen |
|---|---|---|
| `X-Twilio-Email-Event-Webhook-Signature` | Firma Ed25519 en base64 | SendGrid |
| `X-Twilio-Email-Event-Webhook-Timestamp` | Unix timestamp del envío (string) | SendGrid |

### Body

Array JSON de eventos. Estructura típica de cada evento:

```json
[
  {
    "email": "juan@example.com",
    "timestamp": 1715472000,
    "event": "delivered",
    "sg_event_id": "sg_evt_xyz",
    "sg_message_id": "sg_msg_xyz",
    "custom_args": {
      "correlation_id": "uuid-abc-123"
    }
  },
  {
    "email": "pedro@example.com",
    "timestamp": 1715472001,
    "event": "bounce",
    "type": "hard",
    "reason": "550 5.1.1 user unknown",
    "custom_args": {
      "correlation_id": "uuid-def-456"
    }
  }
]
```

## Response

### 200 OK — batch persistido

```json
{ "received": 2, "webhook_event_id": 1024 }
```

### 400 Bad Request — payload no parseable

```json
{ "error": "invalid_payload", "detail": "expected JSON array" }
```

### 401 Unauthorized — firma inválida o ausente

```json
{ "error": "invalid_signature" }
```

## Invariantes

- El endpoint **nunca** procesa eventos inline; persiste el batch en `webhook_events` con `status = pending`.
- Si la verificación de firma falla, no se persiste nada.
- El tiempo de respuesta p95 esperado: < 100 ms.
- Idempotencia a nivel webhook: SendGrid puede reintregrar el mismo batch. El sistema lo persiste como una nueva fila en `webhook_events` (append-only). La deduplicación a nivel `sg_event_id` queda fuera del alcance de esta fase.
