# frozen_string_literal: true

module Admin
  class MockDataGenerator
    Result = Struct.new(:rules_seeded, :blacklist_seeded, :audits_added, :queue_items_added, keyword_init: true)

    MOCK_RULES = [
      { notification_type: "birthday",      channels: %w[email], priority: "standard",   max_per_day: 1  },
      { notification_type: "invoice",        channels: %w[email], priority: "critical",   max_per_day: 10 },
      { notification_type: "password_reset", channels: %w[email], priority: "critical",   max_per_day: 5  },
      { notification_type: "promo",          channels: %w[email], priority: "bulk",       max_per_day: 3  },
      { notification_type: "system_alert",   channels: %w[email], priority: "critical"                    }
    ].freeze

    MOCK_BLACKLIST = [
      { recipient_canonical: "bounce@example.com",  scope: "global",  target: nil,     source: "hard_bounce", reason: "550 5.1.1 mailbox does not exist" },
      { recipient_canonical: "spam@example.com",    scope: "global",  target: nil,     source: "spamreport",  reason: "marked as spam" },
      { recipient_canonical: "nopromo@example.com", scope: "type",    target: "promo", source: "admin_ui",    reason: "opted out of promotions" }
    ].freeze

    MOCK_RECIPIENTS = %w[alice@example.com bob@example.com carol@example.com dave@example.com].freeze
    MOCK_TYPES      = %w[birthday invoice password_reset promo system_alert].freeze
    MOCK_STATUSES   = %w[delivered filtered failed].freeze

    def call
      rules_seeded     = seed_rules
      blacklist_seeded = seed_blacklist
      audits_added     = seed_audits
      queue_items      = seed_queue

      Result.new(
        rules_seeded:     rules_seeded,
        blacklist_seeded: blacklist_seeded,
        audits_added:     audits_added,
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

    def seed_blacklist
      rows = MOCK_BLACKLIST.map { |r| r.merge(created_at: Time.current) }
      result = NotificationBlacklist.insert_all(rows, unique_by: :idx_blacklist_unique)
      result.rows.length
    end

    def seed_audits
      20.times do
        NotificationAudit.create!(
          correlation_id:      SecureRandom.uuid,
          status:              MOCK_STATUSES.sample,
          channel:             "email",
          source:              "internal",
          notification_type:   MOCK_TYPES.sample,
          recipient_canonical: MOCK_RECIPIENTS.sample
        )
      end
      20
    end

    def seed_queue
      5.times do
        DispatchQueue.create!(
          event_id:        rand(1..9999),
          priority:        "standard",
          status:          "pending",
          attempts:        0,
          next_attempt_at: Time.current
        )
      end
      5
    end
  end
end
