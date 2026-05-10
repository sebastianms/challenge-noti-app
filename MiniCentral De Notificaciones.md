**Propuesta Técnica: Mini-Central de Notificaciones**

Sebastián Alonso Machuca Sáez

**Alcance de esta propuesta:** cubre **Parte 1** (mini central de notificaciones) y **Parte 2** *(filtro spam y auditoría consultable) del enunciado. Las menciones a "Roadmap de escalabilidad" se refieren a evoluciones posteriores al alcance pedido (Kafka, microservicio dedicado, rate limiter coordinado, y nuevos proveedores de notificaciones).*

# **1\. Requisitos de la solución**

**Contexto.** 25+ equipos de ingeniería envían notificaciones a sus usuarios sin coordinación, lo que produce cuatro problemas:(a) spam y fatiga comunicacional, (b) inconsistencia de canales y proveedores, (c) alto costo de integración (varios archivos por notificación, errores difíciles de detectar), y (d) ausencia de auditoría.

La solución propuesta es una **Central de Notificaciones como producto interno de plataforma**: un lugar de orquestación que abstrae implementaciones, aplica dominios y gestiona un historial auditable.

| \# | Requisito | DoD (Definition of Done) / Criterio de Éxito |
| :---- | :---- | :---- |
| R1 | \[Minicentral\]Contrato unificado de definición de notificación. | FooNotification \< AbstractNotification con title/body queda invocable vía FooNotification.send(destinatario). |
| R2 | \[Minicentral\]Extensibilidad a nuevos canales sin tocar definiciones existentes. | Agregar Slack/WhatsApp se hace creando un ChannelStrategy; las 25+ notificaciones existentes no se modifican. |
| R3 | \[Minicentral\]Email vía Sendgrid como único canal (otros canales en Roadmap de escalabilidad). | El envío produce un correo con title→subject y body→contenido. |
| R4 | \[Minicentral\]Idempotencia: 0% duplicados accidentales. | Dos invocaciones equivalentes en la misma ventana producen un solo envío. |
| R5 | \[Filtro+Audtitoria\]Filtro anti-spam configurable desde UI sin necesidad de deploy. | Un stakeholder autorizado ajusta la frecuencia máxima de un tipo y el cambio se aplica en ≤ 5 min. |
| R6 | \[Filtro+Audtitoria\]Historial de auditoría (logs) consultable. | Búsqueda por usuario, subject, fecha/hora o correlation\_id con trazabilidad. |
| R7 | \[Minicentral\]Capacidad sostenida de 500.000 invocaciones/hora (≈ 140 rps). | No se observa disminución en el rendimiento efectuando la carga solicitada. |
| R8 | \[Filtro+Audtitoria\]Blacklist de destinatarios (opt-out global / por tipo / por canal; auto-bloqueo por hard bounces). | Destinatario en blacklist nunca recibe envíos del tipo/canal bloqueado; queda auditado con motivo blacklisted. |

 

**SLOs(Métricas de Éxito del servicio):** latencia de ingesta en percentil 95 \< 50 ms (medido con el uso de APM, ej. New Relic) · throughput 140 rps sostenidos (medido con el uso de APM \+ CloudWatch) · duplicados entregados 0% · errores críticos \< 0.1% (Sentry o APMs) · tiempo de integración de un nuevo evento (DevEx) \< 1 hora.

# **2\. Solución propuesta**

## **2.1. Visión de la solución**

La Central de Notificaciones es un **producto interno de plataforma** que actúa como un único punto de entrada para todas las comunicaciones salientes a usuarios. Sustituye la situación actual (25+ equipos integrando Sendgrid por su cuenta) por un sistema con tres garantías:

**• Una sola forma de definir y enviar una notificación** — un archivo, una línea para enviarla.

**• Una sola fuente de verdad sobre las reglas de envío** — qué canales, con qué frecuencia, agrupado o no, configurable desde una UI sin despliegue.

**• Una sola fuente de verdad sobre el historial** — quién recibió qué, cuándo, por qué canal, y si fue filtrado, por qué motivo.

**Componentes principales del producto:**

**1\. API de notificaciones** (AbstractNotification) — el contrato que usan los 25+ equipos para definir y disparar envíos.

**2\. Motor de reglas y blacklist** — decide para cada evento si se envía, se agrupa, o se filtra (por spam o por opt-out).

**3\. Sistema de auditoría inmutable** — registra cada paso de cada envío con un identificador único de trazabilidad.

**4\. Interfaz de administración (UI Admin/Backoffice)** — la cara visible del producto para stakeholders, soporte y operaciones.

**5\. Pipeline de procesamiento asíncrono** — el sistema o “cerebro” que sostiene 500.000 envíos/hora.

**A quién sirve y cómo:**

| Audiencia | Lo que obtiene |
| :---- | :---- |
| Equipos de ingeniería (los 25+) | Una API simple para integrar notificaciones nuevas en menos de 1 hora. No tocan código de envío, no manejan retry, no eligen proveedor, sólo invocan. |
| Stakeholders autorizados | Control total sobre canales, frecuencia y agrupación desde una UI, sin pedirle a ingeniería que despliegue. |
| Soporte / Customer Success | Capacidad de responder "¿por qué Juan no recibió el email?" en segundos, con timeline/trazabilidad completa. |
| Compliance / Legal | Auditoría inmutable y gestión transparente de opt-outs y blacklists. |
| Equipo DevOPS o SRE | Punto único de control para optimizar costos, monitorear salud y responder a incidentes. |

 

**Objetivo del producto:** *Un equipo define una notificación en un archivo. La plataforma decide cómo, cuándo y por dónde se entrega, respeta los opt-outs del usuario, evita spam, y deja registro de todo.*

## **2.2. Interfaz de administración (UI Admin)**

La UI Admin es la **cara visible del producto** y se implementa como un módulo del back-office del monolito (reutilizando el framework de admin existente y el SSO actual; sin SPA nueva, sin infra adicional). El acceso se controla por roles: admin, product, support, engineering.

**Pantallas principales:**

**1\. Dashboard general** — vista 360° del producto. Volumen de envíos por tipo y canal, tasa de filtrado por spam, **estimación de ahorro de costos** (llamadas a Sendgrid evitadas por consolidación), salud del sistema (queue depth, DLQ, error rate). Para stakeholders: comunicar impacto a stakeholders. Para líderes técnicos: detección temprana de anomalías.

**2\. Gestión de reglas** (satisface R5). Lista de tipos de notificación (WelcomeNotification, CommentNotification, etc.) editables: canales habilitados, frecuencia máxima por usuario/día, cooldown, política de agrupación, prioridad. *Caso típico:* un stakeholder autorizado reduce la frecuencia de marketing de 3/día a 1/día y activa resumen semanal — desde la UI, sin código ni deploys..

**3\. Auditoría y búsqueda de envíos** (satisface R6). Búsqueda por usuario/ subject / correlation\_id / tipo / rango de fechas / estado. Por cada envío: timeline completo, trazabilidad de la regla aplicada, payload, motivo (si fue filtrado). *Caso típico:* soporte recibe "no me llegó el código MFA"; La UI muestra que fue filtrado por blacklist (hard bounce previo).

**4\. Gestión de blacklist** (satisface R8). Tabla de destinatarios bloqueados con scope (global / por tipo / por canal), motivo (user\_opt\_out / hard\_bounce / admin) y fuente. Acciones: agregar manualmente, remover (con audit trail), exportar para reportabilidad o compliance.

**5\. Editor de templates**. Vista previa del template individual (title \+ body) y del digest\_template cuando se agrupan N items(resumen). Las variables disponibles las define el equipo emisor en código; el stakeholder autorizado edita el copy y el layout.

**6\. Operaciones / DLQ** . Mensajes en Dead Letter Queue agrupados por motivo de fallo, con reintento individual o masivo. Métricas operacionales en tiempo real (ej: queue depth por prioridad,tasa de 5xx y 429 contra Sendgrid).

**Estrategia de adopción.** Entrega incremental: primero (1) Dashboard \+ (2) Reglas para stakeholders, luego (3) Auditoría \+ (4) Blacklist para soporte, luego (5) Templates y (6) DLQ para operaciones.

## **2.3. Arquitectura técnica: pipeline de cuatro capas**

Habiendo definido qué hace el producto, esta sección explica **cómo se implementa**. La Central se construye como un módulo dentro del monolito Rails, estructurado como un **pipeline de cuatro capas desacopladas mediante el patrón Strategy**, lo que permite intercambiar broker, proveedor y canal sin afectar a los 25 equipos integrados.

**A. Ingesta (DevEx).** AbstractNotification.send construye un evento de negocio y calcula un hash de idempotencia determinista: SHA256(recipient\_id \+ notification\_type \+ context\_id \+ window\_timestamp). Siendo el context\_id un identificador del objeto a notificar (ej: comment\_id, transaction\_id…etc). El window\_timestamp es el epoch de ejecución truncado a una ventana de tiempo fija (ej: 10:01 \-\> 10:00, 10:05 \-\> 10:00). Se persiste en notification\_events con UNIQUE \+ ON CONFLICT DO NOTHING: los duplicados son rechazados por Postgres, evitando que avancen.

**B. Decisión (Motor de Reglas).** Antes de evaluar la regla se consulta la **blacklist** (global / por tipo / por canal), alimentada por opt-out manual, hard bounces de Sendgrid (vía webhook) y carga administrativa. Luego se evalúa la regla configurada desde UI Admin: canales habilitados, frecuencia, agrupación, prioridad. Reglas y blacklist se cachean con Rails.cache (:memory\_store, TTL 5 min) sin infraestructura adicional. El motor toma una de cuatro decisiones: **despachar inmediato**, **agrupar** (la notificación debe tener un digest\_template además del individual), **filtrar por blacklist**, **filtrar por regla**.

**C. Broker.** dispatch\_queue particionada por prioridad(critical / standard / bulk) para que MFA y password resets nunca se retrasen por campañas masivas. Los workers consumen con SELECT … FOR UPDATE SKIP LOCKED, Este bloqueo pesimista permite múltiples consumidores en paralelo sin contención extra. **Decisión:** Se usa Postgres como cola porque ya existe en el stack, soporta cómodamente 140 rps, y entrega ACID. El Strategy permite migrar a Kafka/SQS sin afectar a los 25 equipos cuando el volumen lo exija.  
**D. Despacho (Strategy).** El despacho está desacoplado del resto del pipeline mediante el **patrón Strategy**: cada canal de comunicación implementa la interfaz deliver(event, recipient), lo que permite agregar nuevos canales (SMS, Push, Slack) creando una nueva clase sin modificar la lógica existente. Para el ejercicio actual, el único canal activo es EmailChannel.  
EmailChannel integra la API HTTP de Sendgrid mapeando title → subject y body → html\_content, e inyectando un X-Correlation-ID en los headers del request para vincular los logs internos con los de Sendgrid y permitir trazabilidad end-to-end.  
Cuando un envío falla (timeout, error 5xx de Sendgrid, red no disponible), el worker aplica **backoff exponencial**: reintenta tras 1 min, luego 5 min, luego 25 min. Si los tres intentos fallan, el mensaje se mueve a la **Dead Letter Queue (DLQ)** (registrada en la tabla dispatch\_queue con status \= 'failed') donde queda en espera de revision humana. Ningún mensaje se pierde silenciosamente: todo lo que llega a la DLQ queda visible en la pantalla de **Operaciones/DLQ** de la UI Admin, con el motivo del fallo, el payload completo y tres acciones disponibles: reintento individual, reintento masivo (útil para evacuar la cola tras un outage de Sendgrid) y descarte con motivo registrado en auditoría.  
Cuando Sendgrid reporta un **hard bounce** (dirección de email inválida o inexistente) vía webhook, el sistema auto-agrega al destinatario a la blacklist con motivo hard\_bounce, evitando futuros intentos de envío a esa dirección.

**E. Auditoría transversal.** Cada transición (received → validated → enqueued → dispatched → delivered/failed/filtered) se persiste en notification\_audit con payload y metadata en **JSONB \+ índices GIN** para consultas, y un **snapshot** de la regla aplicada. La tabla está **particionada por día**: la purga es un DROP TABLE (operación de metadatos, instantánea, sin Vacuum), evitando degradación de la performance.

## **2.4. Diagrama de arquitectura de software**

| \[25+ equipos\] → FooNotification.send(destinatario)        │        ▼ A. INGESTA (DevEx) — hash idempotencia SHA256 \+ UNIQUE constraint        │        ▼ B. DECISIÓN — Blacklist? → Reglas (Rails.cache TTL 5m)        ├── inmediato      → C. BROKER (queue\_critical/standard/bulk, SKIP LOCKED)        ├── agrupar        → pending\_digests (digest\_template)        ├── blacklist      → audit (filtered: blacklisted)        └── filtrar regla  → audit (filtered: rate\_limited / disabled)        │        ▼ D. WORKERS (EC2) → Channel Strategy \[Email | SMS | Push | Slack ... Roadmap+\]        │ X-Correlation-ID         ▲        │                           │ Hard bounce webhook → auto-blacklist        ▼ E. AUDITORÍA transversal: JSONB \+ GIN, particionada por día, DROP TABLE para purga |
| :---- |

## **2.5. Diagrama de infraestructura (AWS)**

| Internet → ALB → EC2 Auto-Scaling Group (Web \+ Worker)                        │                        ▼                RDS PostgreSQL                ├── Master: dispatch\_queue, events, rules, blacklist                └── Read Replica: auditoría / reportes / UI                        │                        ▼                Sendgrid API (con webhook a Workers para bounces)   Observabilidad: APM (latencias) | CloudWatch (queue depth → auto-scaling)                 Sentry (errores) | Alarmas: queue\_depth, dlq\_size, 5xx\_rate, 429\_rate |
| :---- |

*Sin infraestructura nueva: se reutiliza el cluster EC2 \+ RDS existente.*

## **2.6. Cómo se satisface cada requisito**

| \# | Requisito | Implementación |
| :---- | :---- | :---- |
| R1 | \[Minicentral\]Contrato unificado de definición de notificación. | Clase AbstractNotification con title/body. Un equipo crea un solo archivo para definir una notificación. |
| R2 | \[Minicentral\]Extensibilidad a nuevos canales sin tocar definiciones existentes. | Patrón Strategy sobre ChannelStrategy \+ ChannelRegistry. Las 25+ notificaciones existentes no requieren cambios. |
| R3 | \[Minicentral\]Email vía Sendgrid como único canal (otros canales en Roadmap de escalabilidad). | EmailChannel integra Sendgrid HTTP API con X-Correlation-ID en custom\_args. |
| R4 | \[Minicentral\]Idempotencia: 0% duplicados accidentales. | Hash determinista SHA256 \+ UNIQUE \+ ON CONFLICT DO NOTHING en Postgres. |
| R5 | \[Filtro+Audtitoria\]Filtro anti-spam configurable desde UI sin necesidad de deploy. | notification\_rules editable desde UI Admin, cacheada con Rails.cache memory\_store (TTL 5 min). Soporta digest\_template para envíos agrupados. |
| R6 | \[Filtro+Audtitoria\]Historial de auditoría (logs) consultable. | notification\_audit (JSONB \+ GIN), búsqueda por correlation\_id, subject, fecha/hora o usuario, con trazabilidad. UI Admin lo expone como herramienta de soporte. |
| R7 | \[Minicentral\]Capacidad sostenida de 500.000 invocaciones/hora (≈ 140 rps). | Bloqueo Pesimista: SKIP LOCKED \+ cache de reglas \+ auto-scaling de workers \+ particionamiento diario. |
| R8 | \[Filtro+Audtitoria\]Blacklist de destinatarios (opt-out global / por tipo / por canal; auto-bloqueo por hard bounces). | notification\_blacklist (scope: global/tipo/canal). Tres fuentes: opt-out manual, hard bounce vía webhook, admin UI. |

 

## **2.7. Limitaciones (pros y contras)**

**Pros.** Pragmatismo (sin infra nueva) · DevEx simple (un archivo, una línea para enviar) · idempotencia delegada al motor de BD · auditoría rica (JSONB+GIN) · Roadmap evolutivo: la abstracción sobre el broker permite migrar de Postgres a Kafka sin afectar a los equipos integrados; el Channel Strategy permite agregar nuevos canales sin modificar las notificaciones existentes.

**Contras.** Postgres como cola tiene un techo (\~500-1000 rps cómodos) · consistencia eventual de reglas hasta 5 min entre nodos · acoplamiento al monolito (mitigado con feature flags para hacer roll-out segmentado) · dependencia única de Sendgrid en alcance actual · sin rate limiter proactivo hacia el proveedor (ver R-07 de abajo).

# **3\. Riesgos y análisis costo-beneficio**

| \# | Riesgo | Mitigación | Costo-beneficio |
| :---- | :---- | :---- | :---- |
| R-01 | Postgres como cuello de botella a 3-5x el volumen actual. | \-Bloqueo Pesimista usando SKIP LOCKED\-Particionamiento \-Roadmap Evolutivo → Kafka/SQS/RabitMQ sin afectar a los 25 equipos. | Costo bajo, Alto Valor  |
| R-02 | Muchos registros/día en tabla de auditoría \- DELETE masivos fragmentan e indexan mal. | Range partitioning declarativo diario \+ retención por DROP TABLE (sin Vacuum). | Costo bajo, Alto Valor |
| **R-03** | Cache de reglas (TTL 5 min entre nodos) puede **afectar la consistencia**. | Trade-off aceptado a favor de latencia \<50 ms. Documentado en UI Admin. | Aceptado.Costo bajo / Alto Valor. |
| R-04 | Caída del proveedor (Sendgrid). | DLQ \+ backoff exponencial. | Costo medio, Alto Valor |
| R-05 | Acoplamiento al monolito. | Rollout con feature flags por equipo \+ observabilidad granular. Roadmap: extraer a microservicio exclusivo de Notificaciones. | Costo Alto, Alto Valor |
| **R-06** | **Rate limits y cuotas del proveedor** (Sendgrid: límite por API key, cuota diaria, throttling reputacional; Clientes de correo: límites por dominio). Picos atípicos generan errores 429\. | **Mitigación parcial y reactiva:** cola como buffer \+ DLQ con backoff respeta Retry-After \+ segregación de colas \+ digest reduce volumen.**Gaps reconocidos:** sin rate limiter proactivo coordinado entre workers, sin manejo preventivo de cuotas diarias, sin spreading temporal de envíos masivos, sin diferenciación por proveedor. La arquitectura **no pierde mensajes** pero no tiene **control del throughput**. | Aceptado en alcance actual con deuda técnica explícita. **Priorizado en Roadmap de escalabilidad**.Costo Alto / Alto Valor |
| **R-07** | **\[Riesgo futuro\]** Soporte a zonas horarias distintas afectará la idempotencia | El diseño ya usa TIMESTAMPTZ en Postgres (almacena siempre en UTC) y Rails opera en UTC por configuración. La conversión de zona horaria quedaría solo en la capa de presentación, minimizando el impacto. No requiere cambios en la lógica de idempotencia ni en el broker. | Fuera del alcance actual. Futura evaluación. |


**Sugerencias para observabilidad.** 

Alarmas proactivas que podrían configurarse:  
\- queue\_depth, dlq\_size  
\- sendgrid\_5xx\_rate  
\- sendgrid\_429\_rate  
\- sendgrid\_down

