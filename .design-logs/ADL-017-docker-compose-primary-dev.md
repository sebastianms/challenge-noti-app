# ADL-017 — Docker Compose como camino primario de desarrollo y testing

**Fecha**: 2026-05-12
**Estado**: Aceptado

## Contexto

El proyecto necesita un entorno de desarrollo reproducible que funcione sin instalar Ruby, PostgreSQL ni dependencias del sistema en el host. El objetivo es que cualquier colaborador llegue a `bin/rspec` verde en menos de 15 minutos desde un `git clone`.

## Decisiones

### 1. Docker Compose como único entorno soportado

El README documenta exclusivamente el flujo `docker compose up -d --build` + `docker compose exec app`. No se documenta un flujo de instalación local (rbenv/asdf + bundle install + postgres local).

**Razón**: Garantiza paridad entre entornos (dev, CI, onboarding). Un setup local requiere gestionar versiones de Ruby, extensiones de PostgreSQL (pgcrypto, pg_partman) y variables de entorno — cada paso es una fuente de divergencia. Docker encapsula todas estas dependencias en el `Dockerfile`.

### 2. Servicio `test` separado del servicio `app`

El `docker-compose.yml` define un servicio `test` con `DATABASE_URL` apuntando a una base de datos de test separada (`challenge_noti_app_test`). Los tests se corren con `docker compose run --rm test bundle exec rspec`.

**Razón**: Separar el servicio `test` evita que `docker compose exec app rspec` use accidentalmente la base de datos de desarrollo. El servicio `test` hereda la imagen del `app` pero sobrescribe variables de entorno relevantes, manteniendo el estado de la DB de dev intacto durante una suite larga.

### 3. Servicio `worker` dedicado

Se define un servicio `worker` con el comando `bin/rails worker:run[10,2]` que corre independientemente del proceso web. Ambos comparten la misma imagen.

**Razón**: Refleja la topología de producción donde web y worker son procesos separados (potencialmente en pods/dynos distintos). Permite testear comportamiento de cola real sin hacks de `inline` mode en desarrollo.

### 4. Perfil `load-test` para k6

El servicio `k6` está bajo el perfil `load-test` y solo se levanta con `docker compose --profile load-test up k6`. La imagen `grafana/k6` se usa directamente sin build custom.

**Razón**: El load test es una operación ocasional (pre-release o benchmarking puntual), no parte del flujo cotidiano. El perfil evita que `docker compose up` levante k6 por defecto y consuma recursos innecesariamente.

### 5. Volumen montado para código fuente en desarrollo

El `docker-compose.yml` monta `.:/rails` (o equivalente) para que los cambios en el host sean visibles inmediatamente en el contenedor sin rebuild.

**Razón**: Permite el flujo de editar en el editor del host y ver cambios reflejados en el servidor sin `docker compose build`. En producción / CI se usa `COPY` en el Dockerfile para una imagen inmutable.

## Consecuencias

- El onboarding se reduce a: `git clone`, `docker compose up -d --build`, `docker compose exec app bin/rails db:setup`.
- El CI (GitHub Actions) usa `docker compose run --rm test` para garantizar el mismo entorno que el dev local.
- Los comandos de documentación siempre son del tipo `docker compose exec app bin/rails ...` — no hay ambigüedad sobre dónde correr algo.
- Si en el futuro se migra a Dev Containers o Codespaces, el `Dockerfile` existente es la base natural.
