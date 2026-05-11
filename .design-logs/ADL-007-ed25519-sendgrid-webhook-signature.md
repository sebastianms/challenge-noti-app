# ADL-007: Verificación de webhooks SendGrid con Ed25519

**Fecha**: 2026-05-11
**Estado**: Aceptado
**Feature**: 003-audit-query (Webhooks::SendgridEventsController)

## Contexto

SendGrid firma sus Signed Event Webhooks v3 con Ed25519 (ECDSA sobre curva edwards25519). El payload firmado es `timestamp || raw_body` y la firma viaja codificada en Base64 en el header `X-Twilio-Email-Event-Webhook-Signature`. La clave pública del cliente se obtiene desde el panel de SendGrid y debe verificarse en cada request para garantizar que el POST viene realmente de SendGrid y no ha sido modificado en tránsito.

OpenSSL trae soporte para Ed25519 desde 1.1.1, pero la API de Ruby `OpenSSL::PKey` para Ed25519 es engorrosa (requiere construir un `PKey` desde DER, ASN.1 wrapping) y propensa a errores. Existe la gema [`ed25519`](https://github.com/RubyCrypto/ed25519) (~1.4) que expone `Ed25519::VerifyKey#verify(signature, message)` con interfaz directa.

## Decisión

Usar la gema `ed25519` (~> 1.3) para verificar firmas de webhooks SendGrid. El módulo `SendgridSignature` encapsula:

- Decodificación de la public key (Base64 → bytes)
- Construcción del `Ed25519::VerifyKey`
- Verificación de `timestamp || payload` contra la firma decodificada
- Captura de `Ed25519::VerifyError` y `ArgumentError` → retorna `false`
- Raise explícito `SendgridSignature::MissingPublicKey` si la env var no está seteada (en lugar de retornar false silenciosamente, que ocultaría mala configuración)

## Alternativas consideradas

1. **`OpenSSL::PKey.new_raw_public_key(:ed25519, bytes)`** — soportado en OpenSSL 1.1.1+. Rechazada: API ergonómicamente peor, requiere wrapping DER, dependencia de versión específica de OpenSSL. Adoptarla cambiaría una gema explícita por un acoplamiento implícito a libssl del sistema.
2. **`rbnacl`** — wrapper de libsodium con Ed25519. Rechazada: dependencia binaria adicional (libsodium) que tendría que instalarse en runtime + CI. La gema `ed25519` es Ruby puro + extensión nativa pequeña, sin dependencias externas.
3. **No verificar firma y confiar en IP allowlist** — Rechazada: SendGrid no garantiza IPs estables y el control de integridad del payload es independiente del origen.

## Consecuencias

**Positivas**:
- API limpia (`SendgridSignature.verify(payload:, signature:, timestamp:, public_key:) → true/false`).
- Una sola gema (~30 KB) añadida al bundle, sin dependencias del sistema.
- Tests deterministas: el helper `SendgridWebhookSigner` genera pares de llaves y firma payloads on-demand sin necesitar fixtures externos.

**Negativas / riesgos**:
- Mantenimiento de la gema depende de la comunidad de RubyCrypto. Es un proyecto estable y maduro, pero implica un punto de auditoría adicional para Brakeman/bundler-audit.
- Si SendGrid rota algún día su algoritmo de firma (ej. Ed448), habrá que reemplazar la gema. La interfaz `SendgridSignature.verify` aísla ese cambio.

## Referencias

- [SendGrid Signed Event Webhook docs](https://www.twilio.com/docs/sendgrid/for-developers/tracking-events/getting-started-event-webhook-security-features#signed-event-webhook-requests)
- [RubyCrypto/ed25519 gem](https://github.com/RubyCrypto/ed25519)
- Implementación: `app/central/webhooks/sendgrid_signature.rb`
- Tests: `spec/central/webhooks/sendgrid_signature_spec.rb`
