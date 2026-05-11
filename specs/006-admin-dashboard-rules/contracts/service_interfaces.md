# Service interfaces — 006-admin-dashboard-rules

## `Admin::DashboardMetrics`

```ruby
class Admin::DashboardMetrics
  WINDOW = 24.hours
  CACHE_KEY = "admin:dashboard:snapshot:v1".freeze
  CACHE_TTL = 30.seconds

  # Devuelve un Hash con los 4 KPIs.
  # @return [Hash{Symbol => Object}]
  def snapshot
    cached = Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { compute_cacheable }
    cached.merge(queue_depth: live_queue_depth, dlq_size: live_dlq_size)
  end

  private

  def compute_cacheable
    {
      volume_by_type_channel: ...,
      filter_rate_by_reason:  ...,
      error_rate_by_channel:  ...
    }
  end
end
```

**Garantías**:
- `snapshot` siempre retorna las 5 claves (`volume_by_type_channel`, `filter_rate_by_reason`, `queue_depth`, `dlq_size`, `error_rate_by_channel`).
- Sin datos en ventana ⇒ valores `{}` o `0`, NUNCA `nil`.

---

## `Admin::RoleAuthorizer`

```ruby
class Admin::RoleAuthorizer
  PERMISSIONS = {
    "admin"       => %i[dashboard rules mock_data].freeze,
    "product"     => %i[dashboard rules].freeze,
    "engineering" => %i[dashboard].freeze,
    "support"     => %i[dashboard].freeze
  }.freeze

  def self.allow?(role, section:)
    PERMISSIONS.fetch(role.to_s, []).include?(section)
  end
end
```

Uso en controllers:
```ruby
before_action :authorize_section!

def authorize_section!
  return if Admin::RoleAuthorizer.allow?(current_admin_user.role, section: controller_section)
  render "errors/forbidden", status: :forbidden
end
```

---

## `Admin::MockDataGenerator`

```ruby
class Admin::MockDataGenerator
  Result = Struct.new(:rules_count, :audits_count, :queue_count, :blacklist_count, keyword_init: true)

  def initialize(seed: SecureRandom.hex(4))
    @seed = seed
  end

  def call
    ActiveRecord::Base.transaction do
      rules     = ensure_demo_rules        # find_or_create_by
      audits    = generate_audits(50)      # mix delivered/failed/filtered
      queue     = generate_queue_items(7)  # 5 pending + 2 dlq
      blacklist = ensure_blacklist(3)      # insert_all unique_by
      Result.new(rules_count: rules.size, audits_count: audits, queue_count: queue, blacklist_count: blacklist)
    end
  end
end
```

**Garantías**:
- Reglas idempotentes (`find_or_create_by(notification_type:)`).
- Blacklist idempotente (`insert_all` con `unique_by: :idx_blacklist_unique`).
- Audits y queue items siempre acumulativos.
- Toda la generación en 1 transacción: o todo o nada.

---

## `Admin::MockDataFeature`

```ruby
module Admin::MockDataFeature
  def self.enabled?
    ENV.fetch("ALLOW_MOCK_DATA_FEATURE", "true") != "false"
  end
end
```

**Default**: enabled (true).
**Disabled**: cuando `ENV["ALLOW_MOCK_DATA_FEATURE"] == "false"` (case-sensitive).
