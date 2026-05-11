# frozen_string_literal: true

require "rails_helper"

RSpec.describe RuleCache do
  before do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  after do
    Rails.cache = @original_cache
  end

  describe ".fetch" do
    it "returns nil when no rule exists for the type" do
      expect(described_class.fetch("unknown")).to be_nil
    end

    it "returns the rule on cache miss and caches it" do
      rule = NotificationRule.create!(notification_type: "welcome")
      expect(described_class.fetch("welcome")).to eq(rule)
    end

    it "does not hit the database on cache hit" do
      NotificationRule.create!(notification_type: "welcome")
      described_class.fetch("welcome")

      query_count = 0
      callback = ->(*, payload) { query_count += 1 if payload[:sql]&.include?("notification_rules") }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        described_class.fetch("welcome")
      end
      expect(query_count).to eq(0)
    end

    it "ignores rules with enabled = false" do
      NotificationRule.create!(notification_type: "welcome", enabled: false)
      expect(described_class.fetch("welcome")).to be_nil
    end
  end

  describe ".invalidate" do
    it "removes the cached entry" do
      rule = NotificationRule.create!(notification_type: "welcome")
      described_class.fetch("welcome")
      rule.destroy
      expect(described_class.fetch("welcome")).to be_nil
    end
  end

  describe "hot reload semantics" do
    it "after_destroy callback also invalidates the cache" do
      rule = NotificationRule.create!(notification_type: "welcome", max_per_day: 3)
      expect(described_class.fetch("welcome")).to eq(rule)
      rule.destroy
      expect(described_class.fetch("welcome")).to be_nil
    end

    it "fresh fetch hits DB after a write (invalidation works synchronously)" do
      NotificationRule.create!(notification_type: "welcome", max_per_day: 3)
      described_class.fetch("welcome")

      NotificationRule.find_by(notification_type: "welcome").update!(max_per_day: 99)

      query_count = 0
      callback = ->(*, payload) { query_count += 1 if payload[:sql]&.include?("notification_rules") }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        expect(described_class.fetch("welcome").max_per_day).to eq(99)
      end
      expect(query_count).to be >= 1
    end
  end

  describe ".clear_all" do
    it "removes all cached rule entries" do
      NotificationRule.create!(notification_type: "a")
      NotificationRule.create!(notification_type: "b")
      described_class.fetch("a")
      described_class.fetch("b")
      described_class.clear_all
      expect(Rails.cache.exist?(described_class.cache_key("a"))).to be false
      expect(Rails.cache.exist?(described_class.cache_key("b"))).to be false
    end
  end

  describe "after_save invalidation" do
    it "reflects updated rule on next fetch" do
      rule = NotificationRule.create!(notification_type: "welcome", max_per_day: 3)
      described_class.fetch("welcome")
      rule.update!(max_per_day: 1)
      expect(described_class.fetch("welcome").max_per_day).to eq(1)
    end
  end
end
