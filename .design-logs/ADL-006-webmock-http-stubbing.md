# ADL-006: WebMock para stubbing de HTTP en tests

**Fecha**: 2026-05-11
**Estado**: Aceptado
**Feature**: 002-email-dispatch (SendgridAdapter / specs)

## Contexto

`SendgridAdapter` realiza llamadas HTTP reales a `https://api.sendgrid.com/v3/mail/send` usando `Net::HTTP`. Los tests no deben enviar requests reales: implican latencia de red, fallos no deterministas, costos de API y riesgo de enviar emails a destinatarios reales en CI.

## Decisión

Usar **WebMock** (`gem "webmock"`) para interceptar y stubbear llamadas HTTP a nivel de socket en toda la suite:

```ruby
# spec/support/webmock.rb
require "webmock/rspec"
WebMock.disable_net_connect!(allow_localhost: true)
```

- `disable_net_connect!` bloquea cualquier request HTTP no stubbeado — si un test olvida el stub, falla rápido con `WebMock::NetConnectNotAllowedError`.
- `allow_localhost: true` permite conexiones a la base de datos PostgreSQL local.
- Los stubs se definen con `stub_request(:post, URL).to_return(status: ...)`.
- Las aserciones sobre requests enviados usan `have_requested(:post, URL).with(headers: {...})`.

El helper `SendgridStubs` en `spec/support/sendgrid_stubs.rb` encapsula los stubs frecuentes (`stub_sendgrid_success`, `stub_sendgrid_error(status:)`) para evitar repetición en specs.

## Alternativas consideradas

| Alternativa | Problema |
|---|---|
| VCR (cassettes) | Overhead de archivos YAML; dificulta variar respuestas en el mismo test |
| Inyección de HTTP client | Más código de producción para acomodar tests; viola "no test-only code paths" |
| Calls reales contra sandbox | Dependencia de red en CI; lentitud; requiere credenciales de test en entorno |
| `allow_any_instance_of(Net::HTTP)` | Frágil; no verifica URLs ni headers |

## Consecuencias

- Toda llamada HTTP no stubbeada falla inmediatamente en tests — detecta omisiones de stub.
- Los stubs son declarativos y legibles junto al test.
- `WebMock.disable_net_connect!` se aplica globalmente; si se agrega un nuevo adaptador de canal, sus specs necesitan el stub correspondiente.
- Cobertura de `X-Correlation-ID`: `have_requested(...).with(headers: {...})` verifica que el header llega al proveedor.
