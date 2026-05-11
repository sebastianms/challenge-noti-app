# Central de Notificaciones

[![Tests](https://github.com/sebastianms/challenge-noti-app/actions/workflows/test.yml/badge.svg)](https://github.com/sebastianms/challenge-noti-app/actions/workflows/test.yml)
[![RuboCop](https://github.com/sebastianms/challenge-noti-app/actions/workflows/lint.yml/badge.svg)](https://github.com/sebastianms/challenge-noti-app/actions/workflows/lint.yml)
[![Security](https://github.com/sebastianms/challenge-noti-app/actions/workflows/security.yml/badge.svg)](https://github.com/sebastianms/challenge-noti-app/actions/workflows/security.yml)

Plataforma de notificaciones centralizada para equipos internos. Un solo archivo por tipo de notificación, idempotencia garantizada por SHA256 + `UNIQUE` constraint en Postgres.

## Requisitos

- Ruby 3.3
- PostgreSQL 17
- Docker (para desarrollo local)

## Inicio rápido

### Con Docker (recomendado)

```bash
# Levantar base de datos y servidor de desarrollo
docker compose up -d postgres app

# Crear y migrar la base de datos (primera vez)
docker compose exec app bin/rails db:create db:migrate

# Correr los specs dentro del contenedor
docker compose run --rm test
```

### Sin Docker (Rails nativo)

```bash
docker compose up -d postgres       # solo la base de datos
bin/rails db:create db:migrate
bundle exec rspec
```

## Agregar una notificación nueva

Crea un archivo en `app/notifications/`:

```ruby
# app/notifications/birthday_notification.rb
class BirthdayNotification < AbstractNotification
  notification_type :birthday

  def self.title(context = {})
    "¡Feliz cumpleaños, #{context[:name]}!"
  end

  def self.body(_context = {})
    "Hoy te deseamos un excelente día."
  end
end
```

Invócala desde cualquier parte del monolito:

```ruby
result = BirthdayNotification.send("juan@example.com", context: { name: "Juan" })
result.created?        # => true
result.correlation_id  # => "uuid-..."
```

El segundo envío idéntico dentro de la ventana retorna `:duplicate` sin crear una fila nueva.

## Benchmark de carga

```bash
bundle exec rake bench:ingestion[140,60]   # 140 rps × 60 segundos
```

Reporta throughput real, p50/p95/p99 y cantidad de errores. Falla con código de salida 1 si p95 > 50 ms o hay errores.

## Desarrollo

### Con Docker

```bash
docker compose run --rm test                        # suite completa
docker compose run --rm test bundle exec rubocop    # lint
docker compose run --rm test bundle exec brakeman --no-pager
docker compose run --rm test bundle exec bundler-audit
```

### Sin Docker

```bash
bundle exec rspec                        # suite completa
bundle exec rubocop                      # lint
bundle exec brakeman --no-pager          # análisis de seguridad
bundle exec bundler-audit                # auditoría de dependencias
```

### Servicios Docker disponibles

| Servicio | Comando | Descripción |
|----------|---------|-------------|
| `postgres` | `docker compose up -d postgres` | Base de datos PostgreSQL 17 |
| `app` | `docker compose up app` | Rails dev server en `localhost:3000` |
| `test` | `docker compose run --rm test` | Corre `bundle exec rspec` y termina |

## Para integradores

Ver [docs/integrators-guide.md](docs/integrators-guide.md) para elegir la ventana de idempotencia, cuándo pasar `context_id`, y qué casos no cubre la Central.
