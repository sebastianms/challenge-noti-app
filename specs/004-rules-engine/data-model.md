# Data Model — 004-rules-engine

## Tabla nueva: `notification_rules`

```sql
CREATE TABLE notification_rules (
  id                     BIGSERIAL PRIMARY KEY,
  notification_type      TEXT NOT NULL,
  channels               TEXT[],                              -- NULL = sin restricción; [] = bloqueado
  max_per_day            INTEGER,                             -- NULL = sin rate limit
  cooldown_seconds       INTEGER,                             -- NULL = sin cooldown
  digest_window_seconds  INTEGER,                             -- NULL = no agrupa (dispatch inmediato)
  priority               TEXT,                                -- NULL | 'critical' | 'standard' | 'bulk'
  enabled                BOOLEAN NOT NULL DEFAULT TRUE,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT notification_rules_type_unique UNIQUE (notification_type),
  CONSTRAINT notification_rules_priority_check
    CHECK (priority IS NULL OR priority IN ('critical', 'standard', 'bulk')),
  CONSTRAINT notification_rules_max_per_day_positive
    CHECK (max_per_day IS NULL OR max_per_day > 0),
  CONSTRAINT notification_rules_cooldown_positive
    CHECK (cooldown_seconds IS NULL OR cooldown_seconds > 0),
  CONSTRAINT notification_rules_digest_positive
    CHECK (digest_window_seconds IS NULL OR digest_window_seconds > 0)
);

CREATE INDEX notification_rules_enabled_idx ON notification_rules (notification_type) WHERE enabled = TRUE;
```

### Notas
- `notification_type` es la clave funcional; UNIQUE. Si una regla está `enabled=FALSE` se ignora (tratado como "sin regla").
- `channels` es TEXT[] de Postgres. Postgres distingue NULL vs `'{}'` (array vacío) → corresponde al diseño (sin restricción vs bloqueo).
- Constraints CHECK previenen valores ilegales (max_per_day = 0, priority desconocida).

---

## Tabla nueva: `pending_digests`

```sql
CREATE TABLE pending_digests (
  id                  BIGSERIAL PRIMARY KEY,
  notification_type   TEXT NOT NULL,
  recipient_canonical TEXT NOT NULL,
  correlation_id      UUID NOT NULL,
  event_id            BIGINT NOT NULL,
  payload             JSONB NOT NULL,
  rule_snapshot       JSONB NOT NULL,
  dispatch_at         TIMESTAMPTZ NOT NULL,
  status              TEXT NOT NULL DEFAULT 'pending',
  consolidated_into   UUID,
  locked_at           TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pending_digests_status_check
    CHECK (status IN ('pending', 'consolidating', 'consolidated', 'orphaned'))
);

CREATE INDEX pending_digests_dispatch_at_idx
  ON pending_digests (dispatch_at)
  WHERE status = 'pending';

CREATE INDEX pending_digests_group_idx
  ON pending_digests (notification_type, recipient_canonical, status);
```

### Notas
- `rule_snapshot` JSONB persiste `{rule_id, channels, priority, digest_window_seconds}` al INSERT — sobrevive al borrado de la regla (R2).
- `consolidated_into` apunta al `correlation_id` de la fila de `dispatch_queue` que resultó de fusionar (FR-006).
- Índice parcial sobre `dispatch_at WHERE status = 'pending'` acelera la query del scheduler.
- Índice compuesto sobre `(notification_type, recipient_canonical, status)` acelera la agrupación al consolidar.

---

## Cambios al esquema existente

### `notification_audit` — agregar `notification_type`

```sql
ALTER TABLE notification_audit ADD COLUMN notification_type TEXT;

CREATE INDEX notification_audit_rate_limit_idx
  ON notification_audit (notification_type, recipient_canonical, created_at)
  WHERE notification_type IS NOT NULL AND recipient_canonical IS NOT NULL;
```

### Notas
- `notification_type` NULLable para filas viejas. El motor de reglas filtra por NOT NULL.
- El índice cubriente soporta la query de rate limit (R3). Solo indexa filas con ambos campos (parcial).
- `Enqueuer.create_audit` y `Worker.create_audit` deben poblar este campo a partir de `event.notification_type`.

---

## Modelos AR

### `NotificationRule`

```ruby
class NotificationRule < ApplicationRecord
  validates :notification_type, presence: true, uniqueness: true
  validates :priority, inclusion: { in: %w[critical standard bulk], allow_nil: true }
  validates :max_per_day, :cooldown_seconds, :digest_window_seconds,
            numericality: { greater_than: 0, allow_nil: true }

  after_save    { RuleCache.invalidate(notification_type) }
  after_destroy { RuleCache.invalidate(notification_type) }

  scope :active, -> { where(enabled: true) }
end
```

### `PendingDigest`

```ruby
class PendingDigest < ApplicationRecord
  validates :notification_type, :recipient_canonical, :correlation_id, presence: true
  validates :status, inclusion: { in: %w[pending consolidating consolidated orphaned] }
end
```

---

## Decision (value object Ruby, no tabla)

```ruby
class Decision
  attr_reader :kind, :reason, :rule_id, :digest_window_seconds, :priority

  def self.dispatch(rule_id: nil, priority: nil)    = new(:dispatch, rule_id:, priority:)
  def self.digest(rule_id:, window:)                 = new(:digest, rule_id:, digest_window_seconds: window)
  def self.filter(reason:, rule_id:)                 = new(:filter, reason:, rule_id:)

  def dispatch? = @kind == :dispatch
  def digest?   = @kind == :digest
  def filter?   = @kind == :filter
end
```
