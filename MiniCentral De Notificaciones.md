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

---

# **Anexo A — Cómo la construimos: Spec-Driven Development en la práctica**

En esta sección quiero contar **el proceso** detrás del código, no la solución técnica. Antes de empezar, una aclaración importante: **este trabajo no lo hice solo**. Lo construí en colaboración con un asistente IA basado en un modelo de lenguaje grande (Claude), operando como pair programmer asíncrono bajo mi dirección. Yo dirigía las decisiones de producto y los trade-offs arquitectónicos; el asistente ejecutaba los pasos de la metodología, redactaba artefactos, escribía código y proponía alternativas. La intención del anexo es dejar trazabilidad de nuestra dinámica de trabajo, qué decisiones tomamos a meta-nivel y qué situaciones aprendí en el camino. No reemplaza al README ni a los ADLs; los complementa.

## **A.1. Metodología: Spec-Driven Development (SDD)**

Construimos la aplicación usando una metodología que invierte el orden tradicional "código → documentación": **las especificaciones son fuente de verdad y el código las expresa**, no al revés. Antes de escribir una línea de Ruby redactábamos documentos que describían el qué, el porqué y el cómo de la feature, con criterios de éxito medibles. Solo cuando esos documentos cerraban empezábamos a programar.

Cada feature la recorrimos por el mismo ciclo:

```
Constitution → Specify → Clarify → Plan → Tasks → Implement → Replanning
```

| Fase | Producto | Objetivo |
| :---- | :---- | :---- |
| Constitution | `mission.md`, `roadmap.md`, `tech-stack.md` | Carta fundacional del proyecto: misión, fases del roadmap y stack. Restringe todas las decisiones posteriores. |
| Specify | `spec.md` + checklist de calidad | QUÉ y POR QUÉ, sin mencionar tecnología. User stories priorizadas (P1/P2/P3), requerimientos funcionales testeables, criterios de éxito medibles. |
| Clarify | Bloque "Clarifications" dentro del spec | Resolución estructurada de ambigüedades antes de planificar. Máximo cinco preguntas dirigidas, una por ambigüedad relevante. |
| Plan | `plan.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md` | CÓMO. Trade-offs evaluados, alternativas descartadas con justificación, contratos de interfaz, escenarios de validación end-to-end. |
| Tasks | `tasks.md` | Lista ejecutable: cada tarea con ID, ruta de archivo exacta, marcador `[P]` si es paralelizable y label `[USn]` para asociarla a una user story. |
| Implement | Código + tests + ADLs | Ejecución por bloques (Setup → Foundational → US1 → US2 → … → Polish). Cada bloque cierra con un "Block Checkpoint" antes de avanzar. |
| Replanning | Auditoría read-only | Validación cross-feature: lo que dicen los specs vs. lo que existe en disco, roadmap vs. realidad, ADLs faltantes. Se corre entre features. |

La pieza más valiosa fueron los **Block Checkpoints**: al cerrar cada bloque de tareas ejecutábamos secuencialmente *lint sin warnings → suite de tests verde con cobertura ≥ 90% → revisión de Clean Code → ADL si la decisión era nueva o contradecía uno previo → commit pequeño y temático → push*. La regla de oro que fijé fue **"lint y tests primero, commit después"**: nunca diferir warnings a "lo arreglo después", porque CI los bloquea igualmente y el ida-y-vuelta de fixes triviales destruye foco.

Los **Architectural Decision Logs (ADLs)** son documentos cortos en `.design-logs/` que registran cada decisión técnica no obvia con cuatro secciones fijas: Contexto · Decisión · Alternativas consideradas · Consecuencias positivas y negativas. Funcionan como memoria institucional: meses después, un nuevo integrante puede entender por qué se eligió `SKIP LOCKED` sobre Redis sin tener que reconstruir el debate.

## **A.2. Las ocho features y su orden**

Descompusimos el roadmap en *shippable slices* — cada feature deja la plataforma en un estado funcional y demostrable. El orden lo dicté estrictamente por dependencias (no se puede auditar lo que no se envía; no se puede filtrar lo que no se decide):

| Feature | Foco | DoD verificado |
| :---- | :---- | :---- |
| 001 — foundational-api | `AbstractNotification` + idempotencia SHA256 + `notification_events` particionado | Una invocación crea exactamente una fila; segunda invocación en misma ventana retorna `:duplicate` |
| 002 — email-dispatch | Broker (`dispatch_queue` + Worker con `SKIP LOCKED`) + EmailChannel/SendgridAdapter + auditoría `enqueued → dispatched → delivered` | Email llega, `correlation_id` propaga vía header y `custom_args` |
| 003 — audit-query | `AuditSearch` con filtros + endpoint Hotwire `/admin/audits` + webhook async SendGrid con verificación Ed25519 + `PartitionManager` | Soporte responde "¿por qué Juan no recibió X?" en segundos |
| 004 — rules-engine | `RulesEngine` (rate limit + cooldown + digest) + `RuleCache` con invalidación sincrónica + `PendingDigest` + `DigestScheduler` | Stakeholders ajustan reglas sin redeploy; aplican en ≤ 5 min |
| 005 — blacklist-bounces | `BlacklistEvaluator` pre-reglas + auto-blacklist desde hard bounce/dropped/spamreport + UI `/admin/blacklist` | Destinatario bloqueado nunca recibe; hard bounce → blacklist en ≤ 30 s |
| 006 — admin-dashboard-rules | Devise + roles (`admin`/`product`/`support`/`engineering`), dashboard de métricas con Chartkick, CRUD de reglas con audit trail (`RuleChange`), mock data con feature flag | Un usuario `product` modifica una regla desde la UI; el cambio se refleja en métricas |
| 007 — admin-ui-audit-blacklist | Migración HTTP Basic → Devise en audits/blacklist, timeline visual por `correlation_id`, filtros `reason`/`rule_id`, CSV export en ambos módulos, `removed_by=email` | Soporte resuelve "¿por qué Juan no recibió X?" en < 30 s desde la UI |
| 008 — admin-templates-dlq | Editor de templates DB-backed (`notification_templates`) con interpolación `{{var}}` y cache 5 min; DLQ operacional con reintento individual/masivo (cap 500) y descarte auditado | Copy editable sin redeploy; DLQ evacuada en < 30 s desde UI |

Cada feature reusó componentes de las anteriores. La 008 toca el núcleo (`AbstractNotification`) por primera vez desde feature 001: el método `resolved_context` convierte `title/body` de dead code a punto de extensión real, sin romper compatibilidad.

## **A.3. Dinámica de colaboración humano + asistente IA**

El trabajo lo llevamos adelante como **pair programming asíncrono**: yo cumplía el rol de driver de producto, arquitecto y decisor de trade-offs, y el asistente IA ejecutaba los pasos de la metodología produciendo artefactos (specs, código, tests, ADLs, commits). El asistente operaba con permisos para leer y escribir archivos y ejecutar comandos en el repo local; yo validaba en cada frontera.

Reglas que fui imponiendo y mantuvimos durante todo el proceso:

1. **Yo decido, la IA ejecuta.** Ante ambigüedades, el asistente NO inventaba: me presentaba 2-4 opciones con la recomendada destacada y el reasoning del trade-off, y esperaba mi respuesta. Las clarificaciones críticas las resolvíamos upfront en la fase Clarify para evitar retrabajo en plan/tasks.

2. **Confirmación explícita en cada frontera.** Yo decía "si" / "sigamos" entre fase y fase. Esto evitó arrancar bloques de tareas sin alineamiento. El asistente nunca avanzaba al siguiente bloque sin mi validación previa.

3. **Commits pequeños y temáticos.** Cada bloque generaba un commit con prefijo `feat|fix|refactor|docs|chore(NNN-feature/bloque): descripción`. Ningún commit cruza features. El historial es legible como una narrativa: `git log --oneline` cuenta el proceso.

4. **Idioma: español neutro.** Toda la comunicación, specs, mensajes de commit y ADLs los escribimos en español. Código y nombres de archivo en inglés. Esta separación permite que la documentación sea accesible al stakeholder y el código mantenga consistencia con el ecosistema técnico.

5. **No backwards-compatibility shims.** Cuando un cambio rompía algo (por ejemplo, agregar `notification_type` a `notification_audit` en feature 004), cambiábamos todo el código de una vez. No quedaron `# removed in v2` ni renames de variables a `_unused`. El historial de Git basta.

## **A.4. Situaciones notables**

Las siguientes son las situaciones que más nos enseñaron sobre el proceso y el stack:

**1. Mismatch de versión de `pg_dump` en CI (feature 003).** Las migraciones corrían localmente con PG 17 pero CI tenía `postgresql-client-16`. El error era oscuro: `pg_dump: server version: 17.9 (Debian); pg_dump version: 16.13`. Fix: agregamos instalación explícita de `postgresql-client-17` en el workflow antes de `db:migrate`. Lección: pinear la versión del cliente, no solo del server.

**2. `travel_to` no afecta a `CLOCK_TIMESTAMP()` (feature 004).** El test del `DigestScheduler` intentaba "avanzar 5 minutos" con `ActiveSupport::Testing::TimeHelpers#travel`, pero PG ignoraba el time-stub porque `CLOCK_TIMESTAMP()` se evalúa server-side. Fix: en lugar de stubbear tiempo, **movimos los datos** (`PendingDigest.update_all(dispatch_at: 1.second.ago)`). Lección: el cliente Ruby puede manipular el tiempo en su proceso, no en el de Postgres. Documentado en ADL-004.

**3. CHECK constraint vs. validación AR redundante (features 004 y 005).** En varios casos el spec exigía constraints a nivel DB (UNIQUE, CHECK), y la pregunta era si duplicar la validación en el modelo AR. Decisión recurrente que tomamos: **sí, defense-in-depth**. La DB protege contra bugs; el modelo da mensajes legibles en la UI. Acepté la duplicación porque cada capa tiene un propósito distinto.

**4. JSONB snapshot vs. FK en `pending_digests` (feature 004).** Cuando un item queda esperando consolidación, la regla que lo originó puede borrarse. Evaluamos tres alternativas: `ON DELETE CASCADE` (viola FR-010), `ON DELETE SET NULL` (huérfano sin contexto), `ON DELETE RESTRICT` (UX confuso). Elegí **JSONB snapshot inline**, sin FK. Documentado en ADL-009. Lección: la integridad referencial estricta no siempre es la respuesta correcta; a veces el snapshot de valor es más fiel al modelo de negocio.

**5. Webhook unificado vs. controllers separados (features 003 y 005).** El roadmap original mencionaba `Webhooks::SendgridBouncesController`. En feature 003 ya habíamos construido un webhook unificado (`POST /webhooks/sendgrid`) con verificación Ed25519 que procesa todos los tipos de eventos. Crear un controller separado en feature 005 habría sido duplicación. Decidí **extender** `WebhookEventWorker#process_event` con una rama `hard_failure?`. Documentado en R3 de `005-blacklist-bounces/research.md`. Lección: el roadmap es un documento vivo; replanificar es legítimo cuando el aprendizaje invalida una decisión previa.

**6. Replanning detecta un nombre de carpeta inconsistente.** Al cerrar feature 004 corrimos una auditoría cross-feature. Detectó que parte de la documentación interna hablaba de `app/central/auditing/` cuando el código real vive en `app/central/audit/` (singular). No lo marcamos como error de implementación: el código es la fuente de verdad, lo que actualizamos fueron las notas de referencia. Lección: Replanning no es para reescribir código, es para reconciliar especificaciones con realidad.

**7. ADLs como memoria de decisiones.** Acumulamos diez Architectural Decision Logs (`ADL-001` a `ADL-010` en `.design-logs/`). Los que más volvimos a consultar fueron ADL-005 (`SKIP LOCKED` como mecanismo de claiming, que terminamos reusando tres veces: worker de email, worker de webhook, scheduler de digests) y ADL-001 (elección de la clave de particionamiento por ventana de idempotencia). Lección: un ADL bien escrito nos ahorró horas de debate semanas después; el costo de escribirlo es de 10 minutos.

**8. UNIQUE con `NULLS NOT DISTINCT` para idempotencia de blacklist (feature 005).** Cuando el webhook de SendGrid procesa un hard bounce, necesitábamos que un segundo evento idéntico no duplicara la fila. La trampa: una blacklist `scope=global` tiene `target IS NULL`, y por default Postgres trata `NULL ≠ NULL` en índices únicos, así que dos filas `(recipient, global, NULL)` para el mismo destinatario serían aceptadas. Solución: PG 15+ permite `CREATE UNIQUE INDEX ... NULLS NOT DISTINCT`, lo que trata `NULL` como un valor más a efectos de unicidad. Combinado con `insert_all(..., unique_by: :idx_blacklist_unique)` da `ON CONFLICT DO NOTHING` idempotente. Lección: features modernas de Postgres a veces resuelven en una línea lo que en aplicación tomaría 20.

**9. Benchmark de SC-005 mejor de lo proyectado (feature 005).** El spec exigía que `BlacklistEvaluator.match` tuviera p95 ≤ 5 ms con 100 000 filas. La query única con OR sobre `(recipient_canonical, scope, target)` + `LIMIT 1` resultó dar **p95 = 1.4 ms y avg = 0.87 ms** — casi 4× mejor que el target. El índice `idx_blacklist_lookup` se aprovecha incluso con la condición OR porque la cardinalidad por destinatario es bajísima (1-3 filas típicamente). Lección: a veces lo que parece "una pre-optimización innecesaria" (definir el target de performance en spec, no después) es justamente lo que te permite verificar que el diseño no degrada bajo carga real.

**10. `Devise.mappings` vacío hasta que se dibujan las rutas (feature 006).** En los request specs de Devise el helper `sign_in(user)` lanza `"Could not find a valid mapping"` porque el servicio de test (`docker compose run --rm test`) no pre-dibuja las rutas. La causa raíz: `Devise.mappings` es un hash que se popula al llamar a `devise_for` en `routes.rb`, y eso solo ocurre cuando Rails dibuja las rutas por primera vez. Fix: agregar `Rails.application.reload_routes!` en el bloque `before(:suite)` de `rails_helper.rb`, justo después de `eager_load!`. Lección: las gemas que registran estado global en tiempo de routing (como Devise) requieren forzar el dibujado de rutas antes del primer test.

**11. `Rails.cache` con `:null_store` en test env rompe specs de cache hit (feature 006).** `config/environments/test.rb` usa `config.cache_store = :null_store` para no interferir entre tests. Eso hace que el spec que verifica "segunda llamada retorna el mismo resultado sin nueva DB query" siempre falle: el null store no guarda nada. Fix: un bloque `around` en el spec que reemplaza `Rails.cache` temporalmente con `ActiveSupport::Cache::MemoryStore.new` y lo restaura en `ensure`. Lección: los stores de cache tienen contratos distintos en test vs. producción; el spec de cache hit requiere un store real, aunque sea en memoria.

**12. Las lambdas en `describe` capturan `self` del contexto de clase, no del ejemplo (feature 006).** La primera versión del spec de role gates definía `GUARDED_ROUTES = { dashboard: -> { get admin_dashboard_path } }`. Al ejecutarse, `get` no estaba disponible porque la lambda capturaba el `self` del nivel de clase (donde `get` es `Module#get`, no el helper de request specs). Fix: reescribir con un método de instancia `def request_for(section)` dentro del describe, que sí se evalúa en el contexto del ejemplo. Lección: en RSpec, los bloques de configuración (`let`, `before`, `subject`) y los helpers (`get`, `post`) son métodos de instancia del ejemplo; las lambdas definidas fuera no los ven.

## **A.5. Métricas del proceso**

Al cerrar feature 008 (Phase 9 del roadmap — UI Admin Templates + DLQ):

| Métrica | Valor |
| :---- | :---- |
| Features completadas | 8 (001–008) — MVP + UI Admin Panel completo |
| Tasks ejecutadas | 312 sobre 312 (39 + 36 + 46 + 45 + 40 + 50 + 23 + 33) |
| Specs en `specs/` | 8 features × (spec + plan + research + data-model + contracts + quickstart + tasks) ≈ 57 documentos |
| ADLs documentados | 14 (ADL-013: template resolver; ADL-014: DLQ bulk retry cap) |
| Tests RSpec | 586 ejemplos · 99.46% de líneas (913/918) |
| Lint warnings | 0 en ~198 archivos Ruby |
| Brakeman + bundler-audit | 0 issues (Devise actualizado de 4.9.4 a 5.0.4 por CVE-2026-32700) |
| Benchmark SC-002 | p95 = 2.19 ms con 10 000 audits (target ≤ 2 000 ms) |
| Benchmark SC-005 | p95 = 1.4 ms con 100 000 filas (target ≤ 5 ms) |
| Commits | ~82, agrupados por bloque y feature |
| Tiempo aproximado | 8 sesiones de trabajo intensivo, sin retrabajo significativo |

La métrica más relevante para SDD no es ninguna de esas: es **cero retrabajo de spec**. Ningún `spec.md` lo reescribimos tras empezar a implementar. Las clarificaciones las atajamos en la fase Clarify; los trade-offs no obvios los dejamos como ADL. Los bugs que encontramos durante implementación fueron de código, no de diseño.

## **A.6. Qué haríamos distinto la próxima vez**

- **Generar el ADL antes del primer commit del bloque**, no después. Cuando el commit ya está hecho, el contexto se diluye; escribir el ADL "fresco" es más fiel a las alternativas realmente evaluadas.
- **Empezar el benchmark de SC-005 desde el primer prototipo**, no en Polish. Si el índice está mal diseñado, descubrirlo en la penúltima tarea cuesta más que descubrirlo al principio.
- **Documentar el `[NEEDS CLARIFICATION]` aunque la resolución sea trivial.** Por más obvio que parezca un default, dejarlo escrito en `Assumptions` evita preguntas idénticas en features posteriores.
- **Más Replannings, no solo entre features.** Al menos uno a la mitad de cada user story P1 para detectar deriva temprana.

## **A.7. Conclusión**

SDD no nos eliminó la complejidad — la **trasladó hacia adelante**, al momento donde es más barata de resolver. Cada decisión técnica importante quedó explícita en un ADL; cada cambio en el código tiene una spec que lo justifica; cada test cubre un Functional Requirement testeable. El resultado es un repositorio donde un nuevo integrante puede leer `specs/mission.md → roadmap.md → 00N-feature/spec.md` y reconstruir el porqué de cada línea de código, sin recurrir a tribal knowledge.

Vale la pena cerrar con una reflexión sobre la colaboración con IA: el asistente no reemplazó mi rol de arquitecto ni de decisor, lo **amplificó**. La velocidad para producir specs detallados, ejecutar tests, leer y modificar muchos archivos a la vez, y mantener la disciplina del Block Checkpoint sin saltearse pasos fue mucho mayor que la que hubiera tenido trabajando solo. Pero las decisiones que importan — qué priorizar, qué trade-off aceptar, cuándo replanificar — siguieron siendo mías. La IA propone, el humano dispone. Esa división de roles fue lo que mantuvo la coherencia del proyecto a lo largo de cinco features.

La aplicación está **terminada en su comportamiento mínimo viable y en su tercera capa de UI operativa** (Parte 1 + Parte 2 + UI Admin completa del enunciado): las ocho features — API de notificaciones, dispatch por email, auditoría consultable, motor de reglas configurable, blacklist + bounces automáticos, panel admin con dashboard + CRUD de reglas, UI de auditoría + blacklist con Devise, y editor de templates + gestión de DLQ — están cerradas con sus respectivos DoD verificados, 586 tests verdes y cobertura del 99.46%. Todo el namespace `/admin/*` usa Devise; cero endpoints con HTTP Basic. La phase siguiente del roadmap (observabilidad, hardening de performance) es evolución natural sobre la misma base, sin reescritura.

