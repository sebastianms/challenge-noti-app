# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::MockDataGenerator, type: :service do
  subject(:generator) { described_class.new }

  describe "#call" do
    it "returns a Result struct with all counters" do
      result = generator.call
      expect(result).to respond_to(:rules_seeded, :blacklist_seeded, :audits_added, :queue_items_added)
    end

    it "seeds mock notification rules" do
      expect { generator.call }.to change(NotificationRule, :count).by(5)
    end

    it "seeds blacklist entries" do
      expect { generator.call }.to change(NotificationBlacklist, :count).by(3)
    end

    it "adds 20 audit records each call" do
      expect { generator.call }.to change(NotificationAudit, :count).by(20)
    end

    it "adds 5 queue items each call" do
      expect { generator.call }.to change(DispatchQueue, :count).by(5)
    end
  end

  describe "idempotency" do
    it "does not duplicate notification rules on second call" do
      generator.call
      expect { generator.call }.not_to change(NotificationRule, :count)
    end

    it "does not duplicate blacklist entries on second call" do
      generator.call
      expect { generator.call }.not_to change(NotificationBlacklist, :count)
    end

    it "accumulates audits on second call (not idempotent by design)" do
      generator.call
      expect { generator.call }.to change(NotificationAudit, :count).by(20)
    end

    it "accumulates queue items on second call (not idempotent by design)" do
      generator.call
      expect { generator.call }.to change(DispatchQueue, :count).by(5)
    end
  end
end
