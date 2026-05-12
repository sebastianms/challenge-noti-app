# ADL-016 — Tailwind CDN para diseño del panel admin

**Fecha**: 2026-05-12
**Estado**: Aceptado

## Contexto

El panel admin requería un sistema de estilos consistente sin agregar un pipeline de assets complejo (webpack, esbuild con configuración custom, PostCSS). El proyecto usa Rails 8.1 con importmap, sin node_modules en el flujo principal.

## Decisiones

### 1. Tailwind CDN en lugar de compilación local

Se agregó `<script src="https://cdn.tailwindcss.com"></script>` en los layouts `application.html.erb` y `admin.html.erb`. No hay archivo `tailwind.config.js` ni paso de build.

**Razón**: El panel admin es una herramienta operacional interna, no una SPA de producción pública. El CDN agrega ~450ms en el primer load (frío) pero cero configuración y cero dependencias de build. La alternativa (tailwindcss-rails gem + purge CSS) agrega un paso de compilación que bloquea el flujo Docker-first del proyecto.

**Trade-off aceptado**: El CDN incluye todas las clases de Tailwind (~3MB sin comprimir) vs ~15KB de un bundle purgado. Aceptable para un panel interno con tráfico bajo. Si el proyecto escala a un producto público, migrar a `tailwindcss-rails` con `bin/rails tailwindcss:build` es un cambio localizado en los layouts y el Gemfile.

### 2. Partials compartidos como sistema de diseño mínimo

Se crearon cuatro partials en `app/views/shared/`:
- `_sidebar.html.erb` — navegación con secciones, rol-aware, link activo
- `_flash.html.erb` — mensajes con `data-flash-container` para test targeting
- `_form_errors.html.erb` — errores de validación uniformes
- `_table.html.erb` — tabla base con clase `admin-table`

**Razón**: Sin un design system externo (Flowbite, DaisyUI, etc.), los partials son el mecanismo más simple para garantizar consistencia visual entre las 7 vistas admin. El atributo `data-admin-sidebar` permite verificar la presencia del sidebar en specs de request sin Capybara.

### 3. Sidebar fijo con secciones por dominio

La sidebar organiza las secciones como: Operación (Dashboard, DLQ) → Reglas → Auditoría → Recursos (Tour, Runbook). El título "Noti Central" es un link al dashboard.

**Razón**: Agrupa funcionalidades por flujo operacional natural (monitorear → configurar → revisar). La sección Recursos expone documentación sin salir del contexto del panel.

## Consecuencias

- El panel no requiere `node` ni `yarn` en el contenedor.
- El CDN requiere conectividad a internet en el browser (no funciona en entornos air-gapped).
- Si se agrega un test de performance de frontend, el CDN puede inflar el tiempo de first paint.
- Ruta de salida a producción: reemplazar CDN por `tailwindcss-rails` gem + `bin/rails assets:precompile` en el Dockerfile.
