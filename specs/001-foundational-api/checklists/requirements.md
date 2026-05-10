# Quality Checklist — 001-foundational-api

**Última revisión**: 2026-05-10

## Calidad de la Especificación

- [x] **WHAT/WHY, no HOW**: El spec describe contrato y comportamiento sin nombrar tecnologías (no menciona Rails, Postgres, SHA256, etc.) salvo en `Assumptions` donde es contextual.
- [x] **Audiencia stakeholder**: Lenguaje accesible a Producto y Soporte, no solo a ingeniería.
- [x] **User stories independientemente testeables**: US1 (definir tipo), US2 (idempotencia), US3 (correlation_id) pueden validarse aisladamente.
- [x] **Acceptance scenarios en formato Given/When/Then**: Todos los escenarios siguen la estructura.
- [x] **Edge cases listados**: Recipient vacío, payload no serializable, reloj, normalización, almacén caído.
- [x] **Sin contradicciones**: Las prioridades P1/P1/P2 son coherentes con el roadmap.

## Trazabilidad

- [x] **R1 cubierto**: FR-001..FR-004 + US1 + SC-001.
- [x] **R4 cubierto**: FR-005..FR-008 + US2 + SC-002, SC-005.
- [x] **R7 parcial**: FR-013 + SC-003 (la garantía completa de 140 rps depende también del despacho, no solo ingesta).
- [x] Cada FR mapea a al menos un acceptance scenario o métrica.

## Testabilidad

- [x] **FRs testables y no ambiguos**: Cada uno especifica un comportamiento observable.
- [x] **SCs medibles**: Tiempos, conteos, percentiles concretos.
- [x] **SCs technology-agnostic**: Hablan de "repositorio", "invocaciones", no de tablas o frameworks.

## NEEDS CLARIFICATION

- [x] **Cero marcadores `[NEEDS CLARIFICATION]`** abiertos. Decisiones razonables documentadas en `Assumptions`:
  - Ventana default = 1 minuto.
  - Normalización del `recipient` = lowercase + trim.
  - `correlation_id` = UUIDv4.
  - Formato de `title`/`body` = sin imponer (responsabilidad del canal).

## Próximos pasos

- [ ] Phase 2: Clarify (opcional — el spec quedó suficientemente cerrado, se puede saltar a Plan si el usuario aprueba).
- [ ] Phase 3: Plan (diseño técnico detallado, incluyendo DDL, módulos, contratos internos).
