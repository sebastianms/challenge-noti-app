# Quickstart — Validation Scenarios (009-observability-perf-hardening)

Escenarios end-to-end que un revisor o un developer corren para validar que la feature está completa. Ejecutados todos vía Docker Compose.

---

## E1 — Setup con Docker desde máquina limpia (US4, SC-004)

**Precondición**: máquina con solo `docker`, `docker compose`, `git`. Sin Ruby, sin gemas.

```bash
git clone <repo> challenge-noti-app
cd challenge-noti-app
docker compose up -d --build
docker compose exec app bin/rails db:setup
docker compose exec app bin/rspec
```

**Resultado esperado**: en < 15 min, suite verde (≥ 90% coverage) sin haber instalado nada en host.

---

## E2 — Levantar y probar la aplicación (US4)

```bash
# Stack ya corriendo del E1
open http://localhost:3000/                  # landing visible, sin redirect
open http://localhost:3000/admin/login       # login Devise
# Login con seeds: admin@example.com / contraseña-de-12-chars
docker compose exec app bin/rails console
> BirthdayNotification.send("test@example.com")
# Salir, abrir
open http://localhost:3000/admin/audits      # ver el evento auditado
open http://localhost:3000/admin/dashboard   # ver métricas
```

**Resultado esperado**: el flujo completo funciona vía contenedor sin pasos extras.

---

## E3 — Crear notificación nueva en < 1 hora (US4, SC-005)

```bash
# Crear archivo nuevo
cat > app/notifications/welcome_notification.rb <<'EOF'
class WelcomeNotification < AbstractNotification
  def title(ctx); "Bienvenido, #{ctx[:name]}!"; end
  def body(ctx);  "Gracias por unirte. Tu cuenta está activa."; end
end
EOF

# Probar
docker compose exec app bin/rails console
> WelcomeNotification.send("nuevo@example.com", context: { name: "Ana" })
```

**Resultado esperado**: archivo creado dentro del repo (volumen montado), Rails autoload lo detecta, evento aparece en `/admin/audits`. Total desde cero (incluyendo setup E1): < 60 min.

---

## E4 — Endpoint /metrics (US1, SC-001)

```bash
# Sin auth → 401
curl -i http://localhost:3000/metrics
# Con auth correcta
curl -i -u "$METRICS_BASIC_AUTH_USER:$METRICS_BASIC_AUTH_PASSWORD" \
  http://localhost:3000/metrics
# Performance
time curl -s -u "..." http://localhost:3000/metrics > /dev/null
```

**Resultado esperado**:
- 401 sin credenciales.
- 200 con Prometheus text exposition; contiene `notif_queue_depth`, `notif_dlq_size`, `notif_events_ingested_total`, `notif_dispatch_errors_total`, `notif_bounce_rate_5m`, `notif_webhook_lag_seconds`.
- Latencia < 100 ms p95.

---

## E5 — Load test 140 rps × 1h (US2, SC-002)

```bash
docker compose --profile load-test up k6
# k6 ejecuta scenario.js, escribe out.json en specs/009-.../load/
docker compose exec app bin/load_report \
  specs/009-observability-perf-hardening/load/out.json \
  > specs/009-observability-perf-hardening/reports/load-test-$(date +%Y%m%d-%H%M).md
cat specs/009-observability-perf-hardening/reports/load-test-*.md | tail -30
```

**Resultado esperado**: reporte markdown generado con `verdict: PASS`, `p95 < 200ms`, `error_rate < 0.005`.

**Nota**: en máquina developer local con recursos limitados, puede fallar — documentado como tolerable si la infra subyacente es el cuello de botella. La métrica relevante es que el reporte se genera y refleja la realidad.

---

## E6 — CI bloquea PR con vuln Brakeman (US3, SC-003)

```bash
# En una rama de prueba
git checkout -b test/brakeman-block
echo 'def bad; User.where("name = #{params[:x]}"); end' >> app/controllers/admin/dashboard_controller.rb
git commit -am "intentional sql injection"
git push -u origin test/brakeman-block
gh pr create --title "test brakeman" --body "should fail"
gh pr checks  # → CI rojo
```

**Resultado esperado**: el step de Brakeman en `.github/workflows/ci.yml` falla con exit 1 y reporta la línea/CWE. PR no mergeable.

Cleanup: `git push origin --delete test/brakeman-block`.

---

## E7 — Home page sin sesión (US5, SC-007)

```bash
# Sin login
curl -s http://localhost:3000/ | grep -i "central de notificaciones"
curl -s http://localhost:3000/ | grep -iE "ingesta|decisión|despacho|auditoría"
```

**Resultado esperado**: HTML con título, descripción y los 4 pasos del flujo. Sin redirect (no `Location:` header).

Test de UX cronometrado: abrir `/` en browser, alguien externo identifica qué hace el sistema en < 30 s.

---

## E8 — Diseño consistente en admin (US6, SC-008)

Recorrer manualmente las 6 vistas:
- `/`
- `/admin/dashboard`
- `/admin/rules`
- `/admin/audits`
- `/admin/blacklist`
- `/admin/templates`
- `/admin/dlq`

Checklist visual:
- [ ] Sidebar idéntico en todas las vistas admin
- [ ] Sección activa resaltada
- [ ] Tablas con mismo estilo (padding, header, hover)
- [ ] Botones `btn-primary`, `btn-secondary`, `btn-danger` usados consistentemente
- [ ] Flash messages en `data-flash-container` (top de content)
- [ ] Forms con `_form_errors` partial cuando hay errores

Validación automática: `bundle exec rspec spec/system/admin_visual_consistency_spec.rb` debe pasar.

---

## E9 — Runbook resuelve DLQ saturada (US4, SC-006)

Simulación:
```bash
# Generar 100 jobs failed manualmente o desde mock_data
docker compose exec app bin/rails runner '
  100.times { DispatchQueue.create!(notification_event_id: NotificationEvent.last.id, channel: "email", status: "failed", failed_reason: "TransientError: simulated") }
'
```

Seguir `docs/runbook.md` sección "DLQ saturada":
1. Abrir `/admin/dlq`
2. Ver grupos por motivo
3. Bulk retry del motivo dominante
4. Verificar audit en `/admin/audits`

**Resultado esperado**: ejercicio completo en < 15 min siguiendo solo el runbook, sin ayuda externa.

---

## Validación de cierre

Antes de marcar Phase 10 como `[DONE]` en el roadmap, los 9 escenarios deben pasar y el integration spec `spec/system/observability_polish_walkthrough_spec.rb` debe estar verde.
