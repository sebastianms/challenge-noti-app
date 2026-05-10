**Caso Técnico**

**Instrucciones** 

Como parte de este proceso, te invitamos a diseñar una central de notificaciones��. 

Antes de comenzar, es muy importante que leas bien la definición del problema por el cual decidimos crear esta central. 

Dado que es un problema grande, lo hemos dividido en dos. Solo la primera parte es requerida. Si quieres ir más lejos, puedes pasar a la segunda una vez que hayas completado la primera. 

Por cada parte, se sugiere rellenar la plantilla técnica adjunta en este documento. 

**Definición del problema** 

Spam 

Más de 25 equipos de una empresa crean y notifican a sus usuarios sin control. Por ejemplo, podrían recibir un correo de cumpleaños, otro de recordatorios, otro de encuestas, otro de notificaciones push (y varios otros más) o SMS, todos el mismo día, produciendo todos juntos un problema de *spam*. 

Además, una misma notificación puede enviarse a todos los canales disponibles si el desarrollador olvida aplicar un filtro manual en su implementación. También puede pasar que un error de programación haga que se envíe más de un correo idéntico. 

No existen lineamientos y consistencia de uso e implementación de canales 

Para una misma notificación, los equipos pueden usar los canales que deseen. Por ejemplo, una notificación simple puede llegar vía SMS, o algo urgente solo vía email.  
Además, no están obligados a hacer implementaciones de cada uno de ellos, por lo que algunas están disponibles, por ejemplo, solo para push. Esto significa que el eventual caso de prender o apagar canales implica una comunicación distinta con el cliente (por ejemplo, si se apaga email entonces que no lleguen cosas críticas al teléfono). 

Tickets 

Crear una nueva notificación implica crear varios archivos, en donde se debe definir la notificaciones de los canales con el mismo nombre en todos los archivos. A veces uno se equivoca y demora horas encontrar el error. 

Varias reglas de envío de la notificación son gatilladas manualmente, dificultando mantener una consistencia. Por ejemplo, crear una entidad X podría implicar gatillar desde web pero no desde la api, lo que es un bug. 

Además, los equipos demoran horas encontrando los bugs. 

Auditoría 

Responder a un cliente sobre quien, cuando y como ha sido notificado es un problema. La necesidad de un historial como log de auditoría es recurrente. 

**Parte 1: Mini Central de notificaciones (requerido)** 

El equipo de producto ha definido que desea construir una central de notificaciones, que evite el spam, permita agregar nuevos canales de comunicación fácilmente y permita hacer auditorías de envío a los clientes. 

Para eso, se ha separado el proyecto en varías partes (*slicing*). Para esta tarea, solo te pedimos la parte 1 mostrada a continuación. Si quieres ir más lejos, entonces puedes ir a la siguiente sección, que contiene las otras partes del problema. 

Parte 1: Construir una “mini central de notificaciones” 

1\. Crear una implementación de la API de la definición de una notificación (parte 1.1) 2\. Crear una implementación de la API que utiliza la definición anterior para enviar la notificación. (parte 1.2) 

Requisitos: 

1\. Disponibilizar solo correo electrónico como canal de comunicación.  
2\. Sin perjuicio de lo anterior, debe estar diseñada para poder implementar nuevos 

canales de comunicación (como WhatsApp o Slack) de manera que no requiera 

cambios en la definición de a notificacion (parte 1.1) 

**APIs** 

El objetivo es que cada notificación pueda ser definida utilizando la API de (1.1). Tu tarea consiste en hacer una implementación de estos métodos, crear el correo electrónico y enviarlo según lo definido en (1.2). 

Parte 1.1: API de definición de la notificación: 

class FooNotification \< AbstractNotificacion 

def self.title 

'Título de la notificación' 

end 

def self.body 

'Este es el contenido de la notificación' 

end 

end 

Parte 1.2: API para gatillar el envío: 

\# Luego, podrás llamar a la notificación definida más arriba de la siguiente manera class FooController \< ApplicationController 

def foo 

FooNotification.send( ‘juan\_perez@gmail.com’ )  
end 

end 

**Contexto adicional** 

Para el desarrollo de la solución, puedes suponer que trabajas: 

● En una aplicación monolítica donde los equipos invocarán directamente el método 

*BirthNotification.send()* en sus módulos. 

● La aplicación está montada en un cluster de máquinas AWS EC2 simple. 

● El resto del stack es una base de datos Postgresql. 

● Para el envío de correos, será utilizada la plataforma sendgrid. 

● El método podría ser invocado hasta 500.000 veces por hora. 

**Parte 2: Agregar filtro Spam (requerido)** 

3\. Permita ver el historial de notificaciones enviadas en una interfaz simple 

**Entregables esperados** 

**1\. Documento de plantilla técnica (5 páginas).** 

**\*** Debe ser compartido vía Google Docs a las direcciones de e-mail adjuntas y habilitando los comentarios. 

**Criterios de evaluación** 

Evaluaremos principalmente: 

● Capacidad para explicar y justificar decisiones. 

● Claridad y solidez del diseño.   
No buscamos algo de producción con cobertura de tests o deploy automático. Queremos ver tu **forma de pensar y resolver problemas reales**, y tu capacidad para **comunicar** tus decisiones técnicas.