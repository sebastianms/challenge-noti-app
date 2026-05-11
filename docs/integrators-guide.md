# Guía para Integradores

Esta guía cubre las decisiones prácticas al conectar un nuevo servicio o flujo a la Central de Notificaciones.

## Cómo elegir la ventana de idempotencia

La ventana define cuánto tiempo se considera "el mismo evento". Usarla mal provoca duplicados visibles o silencia eventos legítimos.

| Origen del disparo | Ventana recomendada | Razonamiento |
|--------------------|--------------------|-|
| Webhook externo (retries automáticos) | `1.minute` | Los proveedores reintentan en segundos; 1 min absorbe todos los retries sin silenciar el siguiente ciclo |
| Cron / job periódico | `idempotency_window` igual al intervalo del job | Si el job corre cada hora, la ventana debe ser `1.hour`; así un doble disparo accidental no genera dos notificaciones |
| Acción manual del usuario | `5.minutes` | Los humanos suelen hacer doble clic o recargar; 5 min es suficiente para detectarlo sin afectar flujos legítimos |
| Evento de sistema (deploy, alerta) | `30.minutes` o más | Los eventos de infraestructura suelen propagarse con fanout; ventanas cortas generan duplicados cuando múltiples nodos los disparan a la vez |

```ruby
class InvoicePaidNotification < AbstractNotification
  notification_type :invoice_paid
  idempotency_window 1.hour   # una factura no se paga dos veces en la misma hora
end
```

## Cuándo usar `context_id`

El `context_id` es la clave de negocio que diferencia dos eventos del **mismo tipo** dentro de la misma ventana.

**Úsalo cuando el recipient puede recibir el mismo tipo de notificación más de una vez por ventana:**

```ruby
# Correcto: dos facturas distintas, mismo usuario, misma hora
InvoicePaidNotification.send("ana@empresa.com", context: { id: invoice.id, amount: 1500 })
```

Si no se pasa `context_id`, el sistema usa `"no_context"` como default, lo que hace que el segundo evento sea silenciado como duplicado aunque corresponda a una entidad distinta.

**Omítelo cuando el evento es intrínsecamente único por ventana:**

```ruby
# Correcto: solo existe un cumpleaños por día
BirthdayNotification.send("juan@empresa.com", context: { name: "Juan" })
```

## Lo que la Central NO cubre

- **Entrega garantizada**: la Central registra el evento de forma idempotente, pero no garantiza que el canal downstream (email, push, SMS) haya entregado el mensaje. Eso es responsabilidad del dispatcher que consuma la tabla `notification_events`.
- **Prioridad de canal**: el campo `priority` se almacena pero el enrutamiento por prioridad depende del dispatcher.
- **Notificaciones recurrentes legítimas**: si el mismo evento debe notificarse dos veces en la misma ventana (raro), debe usarse un `context_id` que las distinga, o ajustar la ventana para que no las solape.
- **Opt-out de usuarios**: la Central no gestiona preferencias de notificación. El integrador debe verificar preferencias antes de invocar `send`.

## Checklist de integración

- [ ] Definir `notification_type` en la clase (no usar el default inferido en producción)
- [ ] Elegir `idempotency_window` según la tabla de arriba
- [ ] Pasar `context[:id]` cuando el recipient puede recibir múltiples del mismo tipo
- [ ] Verificar opt-out antes de invocar `send`
- [ ] Testear idempotencia: dos invocaciones equivalentes → segundo resultado es `:duplicate`
