# frozen_string_literal: true

module Admin
  class MockDataGenerator
    Result = Struct.new(:rules_seeded, :templates_seeded, :blacklist_seeded,
                        :audits_added, :queue_items_added, keyword_init: true)

    NOTIFICATION_TYPES = %w[
      password_reset welcome_email invoice_ready
      promo_weekend security_alert digest_daily
    ].freeze

    MOCK_RULES = [
      { notification_type: "password_reset", channels: %w[email], priority: "critical",  max_per_day: 5,  cooldown_seconds: 300  },
      { notification_type: "welcome_email",  channels: %w[email], priority: "standard",  max_per_day: 1                          },
      { notification_type: "invoice_ready",  channels: %w[email], priority: "standard",  max_per_day: 10                         },
      { notification_type: "promo_weekend",  channels: %w[email], priority: "bulk",      max_per_day: 2,  cooldown_seconds: 86400 },
      { notification_type: "security_alert", channels: %w[email], priority: "critical",  max_per_day: 10, cooldown_seconds: 60   },
      { notification_type: "digest_daily",   channels: %w[email], priority: "standard",  max_per_day: 1,  digest_window_seconds: 86400 }
    ].freeze

    MOCK_TEMPLATES = [
      { notification_type: "password_reset", locale: "es",
        title: "Restablece tu contraseña, {{user_name}}",
        body: "Hola {{user_name}}, recibimos una solicitud para restablecer tu contraseña. Haz clic en el enlace (válido por {{expiry_minutes}} min): {{reset_url}}. Si no fuiste tú, ignora este mensaje." },
      { notification_type: "welcome_email", locale: "es",
        title: "¡Bienvenido/a a NotiCentral, {{user_name}}!",
        body: "Hola {{user_name}}, tu cuenta fue creada el {{created_date}}. Puedes comenzar explorando tu panel en {{dashboard_url}}." },
      { notification_type: "invoice_ready", locale: "es",
        title: "Tu factura {{invoice_number}} está disponible",
        body: "Hola {{user_name}}, tu factura del período {{period}} por ${{amount}} está lista. Descárgala desde {{invoice_url}}. Vence el {{due_date}}." },
      { notification_type: "promo_weekend", locale: "es",
        title: "{{discount}}% de descuento este fin de semana — solo para ti, {{user_name}}",
        body: "Aprovecha el descuento exclusivo de {{discount}}% en toda la tienda. Código: {{promo_code}}. Válido hasta el {{expiry_date}}." },
      { notification_type: "security_alert", locale: "es",
        title: "Acceso desde nueva ubicación — {{city}}, {{country}}",
        body: "Hola {{user_name}}, detectamos un acceso a tu cuenta desde {{city}} ({{ip_address}}) el {{datetime}}. Si fuiste tú, no hay nada que hacer. Si no reconoces este acceso, cambia tu contraseña ahora." },
      { notification_type: "digest_daily", locale: "es",
        title: "Tu resumen diario — {{date}}",
        body: "Hola {{user_name}}, estas son las novedades del día: {{summary_items}}. Tienes {{pending_count}} notificaciones pendientes.",
        digest_template: "• {{item_title}} ({{item_date}})" }
    ].freeze

    MOCK_BLACKLIST = [
      { recipient_canonical: "bounce@blackhole.example.com", scope: "global",  target: nil,            source: "hard_bounce",  reason: "550 5.1.1 The email account that you tried to reach does not exist" },
      { recipient_canonical: "spam@disposable.example.com",  scope: "global",  target: nil,            source: "spamreport",   reason: "Recipient marked message as spam" },
      { recipient_canonical: "nopromo@example.com",          scope: "type",    target: "promo_weekend", source: "admin_ui",    reason: "Usuario solicitó baja de promociones" },
      { recipient_canonical: "invalid@nodomain.xyz",         scope: "channel", target: "email",        source: "hard_bounce",  reason: "550 5.4.1 Recipient address rejected: Domain not found" },
      { recipient_canonical: "unsubscribed@example.com",     scope: "global",  target: nil,            source: "admin_ui",     reason: "Unsubscribe request via soporte" }
    ].freeze

    RECIPIENTS = [
      { email: "alice.martin@example.com",   name: "Alice Martin"   },
      { email: "bob.garcia@example.com",      name: "Bob García"     },
      { email: "carol.lopez@example.com",     name: "Carol López"    },
      { email: "dave.smith@example.com",      name: "Dave Smith"     },
      { email: "eva.torres@example.com",      name: "Eva Torres"     },
      { email: "frank.hill@example.com",      name: "Frank Hill"     },
      { email: "grace.wu@example.com",        name: "Grace Wu"       },
      { email: "hector.diaz@example.com",     name: "Héctor Díaz"    }
    ].freeze

    DLQ_FAILURE_CLASSES = [
      { class: "Net::OpenTimeout",            msg: "execution expired after 30s"                              },
      { class: "Net::OpenTimeout",            msg: "connection timed out connecting to smtp.sendgrid.net:465" },
      { class: "Net::OpenTimeout",            msg: "execution expired after 30s"                              },
      { class: "SendGrid::RateLimitError",    msg: "429 Too Many Requests — retry after 60s"                  },
      { class: "SendGrid::RateLimitError",    msg: "429 Too Many Requests — daily limit reached"              },
      { class: "Errno::ECONNREFUSED",         msg: "Connection refused - connect(2) for smtp.sendgrid.net:465" },
      { class: "JSON::ParserError",           msg: "unexpected token at '{\"error\":\"malformed\"'"            },
      { class: "ActiveRecord::Deadlocked",    msg: "Deadlock found when trying to get lock"                   }
    ].freeze

    def call
      rules_seeded     = seed_rules
      templates_seeded = seed_templates
      blacklist_seeded = seed_blacklist
      audits_added     = seed_audit_timelines
      queue_items      = seed_dlq

      Result.new(
        rules_seeded:      rules_seeded,
        templates_seeded:  templates_seeded,
        blacklist_seeded:  blacklist_seeded,
        audits_added:      audits_added,
        queue_items_added: queue_items
      )
    end

    private

    def seed_rules
      MOCK_RULES.count do |attrs|
        record = NotificationRule.find_or_initialize_by(notification_type: attrs[:notification_type])
        record.assign_attributes(attrs.merge(enabled: true))
        record.save! if record.changed?
        record.previously_new_record?
      end
    end

    def seed_templates
      MOCK_TEMPLATES.count do |attrs|
        record = NotificationTemplate.find_or_initialize_by(
          notification_type: attrs[:notification_type],
          locale: attrs[:locale]
        )
        record.assign_attributes(attrs)
        record.save! if record.changed?
        record.previously_new_record?
      end
    end

    def seed_blacklist
      rows = MOCK_BLACKLIST.map { |r| r.merge(created_at: Time.current) }
      result = NotificationBlacklist.insert_all(rows, unique_by: :idx_blacklist_unique)
      result.rows.length
    rescue StandardError
      0
    end

    AuditContext = Struct.new(:correlation, :recipient, :ntype, :payload, :rule_snapshot, keyword_init: true)

    def seed_audit_timelines
      rule          = NotificationRule.first
      rule_snapshot = rule ? { "id" => rule.id, "max_per_day" => rule.max_per_day, "priority" => rule.priority } : nil
      month_start   = Time.current.beginning_of_month
      elapsed_secs  = (Time.current - month_start).to_i
      count = 0

      40.times do |i|
        recipient = RECIPIENTS.sample
        ntype     = NOTIFICATION_TYPES.sample
        ctx = AuditContext.new(
          correlation:   SecureRandom.uuid,
          recipient:     recipient[:email],
          ntype:         ntype,
          payload:       build_payload(ntype, recipient[:name]),
          rule_snapshot: rule_snapshot
        )
        base_time = month_start + rand(0..elapsed_secs).seconds
        count += create_timeline(ctx, base_time, pick_scenario(i))
      end

      count
    end

    def pick_scenario(index)
      case index % 5
      when 0, 1 then :delivered
      when 2    then :filtered
      when 3    then :failed
      when 4    then :webhook_delivered
      end
    end

    def create_timeline(ctx, base_time, scenario)
      count = 0

      case scenario
      when :delivered
        count += write_audit(ctx, status: "enqueued",   at: base_time,             payload: ctx.payload)
        count += write_audit(ctx, status: "dispatched", at: base_time + 2.seconds)
        count += write_audit(ctx, status: "delivered",  at: base_time + 8.seconds)

      when :webhook_delivered
        count += write_audit(ctx, status: "enqueued",   at: base_time,             payload: ctx.payload)
        count += write_audit(ctx, status: "dispatched", at: base_time + 3.seconds)
        count += write_audit(ctx, status: "delivered",  at: base_time + 45.seconds,
                             source: "sendgrid_webhook",
                             meta: { "sg_event_id" => SecureRandom.hex(8),
                                     "ip"          => "#{rand(1..255)}.#{rand(0..255)}.#{rand(0..255)}.1",
                                     "user_agent"  => "Mozilla/5.0 (compatible; Sendgrid)" })

      when :filtered
        reason = %w[rate_limited cooldown_active blacklisted].sample
        count += write_audit(ctx, status: "filtered", at: base_time, payload: ctx.payload,
                             meta: { "reason" => reason, "rule_id" => ctx.rule_snapshot&.dig("id") }.compact)

      when :failed
        count += write_audit(ctx, status: "enqueued",   at: base_time,             payload: ctx.payload)
        count += write_audit(ctx, status: "dispatched", at: base_time + 1.second)
        count += write_audit(ctx, status: "failed",     at: base_time + 30.seconds,
                             meta: { "reason" => "dispatch_error",
                                     "error_class" => DLQ_FAILURE_CLASSES.sample[:class],
                                     "attempts"    => rand(1..3) })
      end

      count
    end

    def write_audit(ctx, status:, at:, source: "internal", payload: nil, meta: nil)
      NotificationAudit.create!(
        correlation_id:      ctx.correlation,
        status:              status,
        channel:             "email",
        source:              source,
        notification_type:   ctx.ntype,
        recipient_canonical: ctx.recipient,
        payload:             payload,
        rule_snapshot:       ctx.rule_snapshot,
        metadata:            meta,
        created_at:          at
      )
      1
    end

    def seed_dlq
      count = 0
      DLQ_FAILURE_CLASSES.each do |failure|
        DispatchQueue.create!(
          event_id:        rand(1..9999),
          priority:        %w[critical standard bulk].sample,
          status:          "failed",
          attempts:        DispatchQueue::MAX_ATTEMPTS,
          failed_reason:   "#{failure[:class]}: #{failure[:msg]}",
          next_attempt_at: Time.current,
          created_at:      Time.current.beginning_of_month + rand(0..(Time.current - Time.current.beginning_of_month).to_i).seconds,
          updated_at:      Time.current - rand(0..86_400).seconds
        )
        count += 1
      end
      count
    end

    def build_payload(ntype, user_name)
      case ntype
      when "password_reset"
        { "user_name" => user_name, "reset_url" => "https://app.example.com/reset/#{SecureRandom.hex(12)}",
          "expiry_minutes" => 30 }
      when "welcome_email"
        { "user_name" => user_name, "created_date" => Date.today.strftime("%d/%m/%Y"),
          "dashboard_url" => "https://app.example.com/dashboard" }
      when "invoice_ready"
        { "user_name" => user_name, "invoice_number" => "INV-#{rand(10_000..99_999)}",
          "period" => Date.today.strftime("%B %Y"), "amount" => rand(100..9999),
          "invoice_url" => "https://app.example.com/invoices/#{rand(1..999)}",
          "due_date" => (Date.today + 15).strftime("%d/%m/%Y") }
      when "promo_weekend"
        { "user_name" => user_name, "discount" => [ 10, 15, 20, 25, 30 ].sample,
          "promo_code" => "PROMO#{rand(100..999)}",
          "expiry_date" => (Date.today + 3).strftime("%d/%m/%Y") }
      when "security_alert"
        { "user_name" => user_name,
          "city" => %w[Buenos\ Aires Córdoba Montevideo Madrid Barcelona].sample,
          "country" => %w[AR AR UY ES ES].sample,
          "ip_address" => "#{rand(1..254)}.#{rand(0..255)}.#{rand(0..255)}.#{rand(1..254)}",
          "datetime" => Time.current.strftime("%d/%m/%Y %H:%M UTC") }
      when "digest_daily"
        { "user_name" => user_name, "date" => Date.today.strftime("%d/%m/%Y"),
          "pending_count" => rand(1..12),
          "summary_items" => "#{rand(2..8)} eventos procesados" }
      else
        { "user_name" => user_name }
      end
    end
  end
end
