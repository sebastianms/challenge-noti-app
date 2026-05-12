# Tour de la aplicación — Central de Notificaciones

Guía práctica para recorrer el panel admin. Cada sección describe el propósito del área, qué roles tienen acceso y una acción típica usando los datos de seed (`db:seed`).

**Pre-requisito**: servidor corriendo (`docker compose up app`) y datos cargados (`docker compose exec app bin/rails db:seed`).

---

## Home

**URL**: `http://localhost:3000/`  
**Roles con acceso**: público (sin login)

### Propósito

Página de presentación del sistema. Explica el flujo de notificaciones en 4 pasos (ingesta → decisión → despacho → auditoría), lista los endpoints disponibles y ofrece un CTA de acceso al panel admin.

### Acción típica

1. Abre `http://localhost:3000/` sin sesión activa.
2. Observa el hero con el nombre del sistema y la descripción.
3. Lee el flujo numerado — cada paso corresponde a una capa del sistema.
4. Haz clic en "Ir al panel" o "Ingresar" para ir al login.

### Qué observar en pantalla

- El botón CTA cambia según el estado de sesión: "Ingresar" si no hay sesión, "Ir al panel" si ya estás autenticado.
- No se requiere autenticación para ver esta página.

---

## Dashboard

**URL**: `http://localhost:3000/admin/dashboard`  
**Roles con acceso**: admin, product, engineering, support

### Propósito

Vista de estado operativo en tiempo real. Muestra métricas de la cola de despacho (pendientes, en vuelo, fallidos), tasa de bounces de los últimos 5 minutos, lag de webhooks y total de eventos ingestados en 24 horas. Es el punto de partida para detectar degradaciones.

### Acción típica

1. Ingresa con `admin@noti-central.local` / `Admin12345678!`.
2. Navega a `/admin/dashboard` (o haz clic en "Dashboard" en la barra lateral).
3. Observa los cards de métricas. Si corriste el load test, verás números reales en "Events ingested 24h".

### Qué observar en pantalla

- **Queue depth**: cuántos eventos están en cola (pending + in_flight). Valor normal en reposo: 0.
- **DLQ size**: entradas fallidas. Cualquier valor > 0 merece atención.
- **Bounce rate 5m**: porcentaje de bounces en la ventana reciente. Normal: 0.0 %.
- **Webhook lag**: segundos desde el webhook más antiguo sin procesar. Normal: 0.0 s.

---

## Reglas

**URL**: `http://localhost:3000/admin/rules`  
**Roles con acceso**: admin, product

### Propósito

Motor de decisión configurable. Permite crear reglas de throttle, cooldown y rate limiting por tipo de notificación. Cada regla tiene un historial de cambios auditado. El motor evalúa las reglas en orden antes de cada despacho.

### Acción típica

1. Ingresa con `product@noti-central.local` / `Admin12345678!`.
2. Ve a `/admin/rules` → haz clic en "Nueva regla".
3. Completa el formulario:
   - **Notification type**: `welcome`
   - **Rule type**: `cooldown`
   - **Parameters**: `{ "window_seconds": 3600 }`
   - **Enabled**: activado
4. Guarda. La regla aparece en la tabla con estado "Activa".
5. Haz clic en "Historial" para ver el log de cambios de esa regla.

### Qué observar en pantalla

- La tabla muestra tipo, estado (activa/inactiva), parámetros y fecha de creación.
- El botón "Historial" está disponible por regla — muestra quién creó o modificó cada versión.
- Solo admin y product pueden crear/editar; engineering y support no ven este menú.

---

## Auditoría

**URL**: `http://localhost:3000/admin/audits`  
**Roles con acceso**: admin, product, engineering, support

### Propósito

Registro inmutable de todos los eventos de notificación. Cada fila corresponde a un intento de despacho o a un evento de webhook de SendGrid. Permite filtrar por correlation ID, tipo, estado y rango de fechas.

### Acción típica

1. Ingresa con cualquier rol (ej. `support@noti-central.local` / `Admin12345678!`).
2. Ve a `/admin/audits`.
3. Usa el campo "Correlation ID" para buscar un evento específico (puedes obtener un ID real desde la consola: `NotificationAudit.last.correlation_id`).
4. Haz clic en la fila para ver el detalle completo (payload, metadata, rule_snapshot).

### Qué observar en pantalla

- Cada fila tiene: correlation ID, tipo de notificación, canal, estado (`sent`, `bounced`, `duplicate`, etc.) y timestamp.
- El detalle de una fila muestra el `rule_snapshot` — la foto de las reglas vigentes en el momento del despacho.
- Source `internal` = enviado por el sistema; `sendgrid_webhook` = actualización de estado recibida de SendGrid.

---

## Blacklist

**URL**: `http://localhost:3000/admin/blacklist`  
**Roles con acceso**: admin, support (lectura + escritura), product, engineering (solo lectura)

### Propósito

Lista de destinatarios excluidos del sistema. Cuando un destinatario está en la blacklist, cualquier notificación dirigida a él se descarta antes del despacho. Soporta opt-outs explícitos y bloqueos administrativos.

### Acción típica

1. Ingresa con `support@noti-central.local` / `Admin12345678!`.
2. Ve a `/admin/blacklist` → haz clic en "Agregar".
3. Ingresa `blocked@example.com` y guarda.
4. Abre la consola Rails y verifica que el envío falla silenciosamente:

```bash
docker compose exec app bin/rails console
```

```ruby
WelcomeNotification.send("blocked@example.com", context: { name: "Test" })
# => result.state → :blocked (o :duplicate si ya existía un evento previo)
```

5. Vuelve al panel y elimina la entrada con el botón "Eliminar".

### Qué observar en pantalla

- La tabla muestra el destinatario, fecha de bloqueo y quien lo agregó.
- El rol `engineering` y `product` ven la lista pero el formulario de alta/baja está deshabilitado.
- admin y support ven el botón "Eliminar" en cada fila.

---

## Templates

**URL**: `http://localhost:3000/admin/templates`  
**Roles con acceso**: admin, product

### Propósito

Editor de plantillas de mensajes por tipo de notificación y canal. Permite personalizar el subject y body sin deployar código. Soporta variables interpoladas con sintaxis `{{variable}}`. La previsualización muestra el resultado renderizado con datos de ejemplo.

### Acción típica

1. Ingresa con `product@noti-central.local` / `Admin12345678!`.
2. Ve a `/admin/templates` → haz clic en "Nueva plantilla".
3. Completa el formulario:
   - **Notification type**: `welcome`
   - **Channel**: `email`
   - **Subject**: `Bienvenido, {{name}}`
   - **Body**: `Hola {{name}}, tu cuenta está lista.`
4. Usa "Previsualizar" para renderizar con variables de ejemplo.
5. Guarda.

### Qué observar en pantalla

- La vista de índice muestra tipo, canal y fecha de actualización.
- "Previsualizar" abre un panel inline con el HTML/texto renderizado.
- Las variables `{{...}}` se destacan visualmente en el editor.

---

## DLQ (Dead Letter Queue)

**URL**: `http://localhost:3000/admin/dlq`  
**Roles con acceso**: admin, engineering

### Propósito

Centro de control para eventos fallidos. Muestra los eventos que agotaron sus reintentos (3 intentos con backoff exponencial: 1 min → 5 min → 25 min). Permite reintentar uno a uno, en bloque, o descartar definitivamente. Es la principal herramienta de guardia cuando la DLQ crece.

### Acción típica

1. Ingresa con `admin@noti-central.local` / `Admin12345678!`.
2. Crea un evento fallido desde la consola:

```bash
docker compose exec app bin/rails console
```

```ruby
# Simular un evento fallido directamente en la cola
event = NotificationEvent.last
DispatchQueue.create!(
  event_id:        event.id,
  priority:        "standard",
  status:          "failed",
  attempts:        3,
  failed_reason:   "Net::ReadTimeout: execution expired",
  next_attempt_at: Time.current
)
```

3. Ve a `/admin/dlq` — verás el evento fallido con su razón de error.
4. Haz clic en "Reintentar" para volver a encolar el evento.
5. O usa "Descartar" para eliminarlo permanentemente de la cola activa.
6. "Reintentar todos" procesa en bloque todos los eventos fallidos visibles.

### Qué observar en pantalla

- Los eventos se agrupan por tipo de error (cuando hay múltiples del mismo origen).
- "Reintentar" cambia el status a `pending` y resetea los `attempts` a 0.
- "Descartar" cambia el status a `discarded` — ya no se reintenta, pero el registro queda en auditoría.
- El botón "Descartar" tiene estilo de peligro (rojo) para evitar clics accidentales.
- Solo admin y engineering tienen acceso a esta sección.
