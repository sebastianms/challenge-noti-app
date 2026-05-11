# Contrato HTTP — Sendgrid v3 Mail Send

**Endpoint**: `POST https://api.sendgrid.com/v3/mail/send`

## Request

### Headers

| Header | Valor | Requerido |
|--------|-------|-----------|
| `Authorization` | `Bearer {SENDGRID_API_KEY}` | Sí |
| `Content-Type` | `application/json` | Sí |
| `X-Correlation-ID` | UUID del evento | Sí |

### Body

```json
{
  "personalizations": [
    {
      "to": [{ "email": "recipient@example.com" }]
    }
  ],
  "from": {
    "email": "notifications@company.com"
  },
  "subject": "Título de la notificación",
  "content": [
    {
      "type": "text/html",
      "value": "<p>Cuerpo de la notificación</p>"
    }
  ]
}
```

**Campos mapeados desde el evento**:
- `subject` ← `NotificationEvent#payload["title"]`
- `content[0].value` ← `NotificationEvent#payload["body"]`
- `to[0].email` ← `recipient_id` (ya validado con `@`)
- `X-Correlation-ID` ← `NotificationEvent#correlation_id`

## Responses

| Status | Semántica | Acción del Worker |
|--------|-----------|-------------------|
| `202 Accepted` | Sendgrid aceptó | → `delivered` |
| `400 Bad Request` | Payload inválido | → DLQ inmediato (permanente) |
| `401 Unauthorized` | API key inválida | → DLQ inmediato (permanente) |
| `413 Payload Too Large` | Body demasiado grande | → DLQ inmediato (permanente) |
| `429 Too Many Requests` | Throttling | → Reintento con backoff |
| `5xx` | Error de Sendgrid | → Reintento con backoff |
| Timeout / red | Fallo de red | → Reintento con backoff |

## WebMock stub para tests

```ruby
stub_request(:post, "https://api.sendgrid.com/v3/mail/send")
  .with(
    headers: { "Authorization" => /^Bearer / },
    body: hash_including("personalizations")
  )
  .to_return(status: 202, body: "", headers: {})
```

## Configuración

| Variable de entorno | Default (dev/test) | Descripción |
|--------------------|--------------------|-------------|
| `SENDGRID_API_KEY` | `"test-key"` | Bearer token de autenticación |
| `SENDGRID_FROM_EMAIL` | `"notifications@company.com"` | Remitente fijo |
