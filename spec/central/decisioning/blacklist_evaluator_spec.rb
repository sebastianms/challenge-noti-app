# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlacklistEvaluator do
  def event_for(recipient:, type: "birthday")
    OpenStruct.new(recipient_canonical: recipient, notification_type: type)
  end

  describe ".match" do
    it "retorna nil cuando no hay fila para el destinatario" do
      expect(described_class.match(event: event_for(recipient: "free@x.com"))).to be_nil
    end

    it "matchea cualquier tipo/canal cuando scope=global" do
      NotificationBlacklist.create!(recipient_canonical: "a@x.com", scope: "global", source: "manual")

      result = described_class.match(event: event_for(recipient: "a@x.com", type: "birthday"))
      expect(result).not_to be_nil
      expect(result.scope).to eq("global")

      result2 = described_class.match(event: event_for(recipient: "a@x.com", type: "marketing"), channel: "sms")
      expect(result2).not_to be_nil
    end

    it "matchea solo el notification_type indicado cuando scope=type" do
      NotificationBlacklist.create!(recipient_canonical: "b@x.com", scope: "type", target: "birthday", source: "manual")

      expect(described_class.match(event: event_for(recipient: "b@x.com", type: "birthday"))).not_to be_nil
      expect(described_class.match(event: event_for(recipient: "b@x.com", type: "marketing"))).to be_nil
    end

    it "matchea solo el channel indicado cuando scope=channel" do
      NotificationBlacklist.create!(recipient_canonical: "c@x.com", scope: "channel", target: "email", source: "hard_bounce")

      expect(described_class.match(event: event_for(recipient: "c@x.com", type: "birthday"), channel: "email")).not_to be_nil
      expect(described_class.match(event: event_for(recipient: "c@x.com", type: "birthday"), channel: "sms")).to be_nil
    end

    it "con múltiples filas matching retorna alguna (LIMIT 1)" do
      NotificationBlacklist.create!(recipient_canonical: "m@x.com", scope: "global", source: "manual")
      NotificationBlacklist.create!(recipient_canonical: "m@x.com", scope: "type", target: "birthday", source: "manual")

      result = described_class.match(event: event_for(recipient: "m@x.com", type: "birthday"))
      expect(result).not_to be_nil
      expect(%w[global type]).to include(result.scope)
    end

    it "matchea por recipient_canonical exacto (canonicalization es responsabilidad del caller)" do
      NotificationBlacklist.create!(recipient_canonical: "lower@x.com", scope: "global", source: "manual")

      expect(described_class.match(event: event_for(recipient: "lower@x.com"))).not_to be_nil
      expect(described_class.match(event: event_for(recipient: "Lower@X.com"))).to be_nil
    end
  end

  describe ".blacklisted?" do
    it "true cuando hay match" do
      NotificationBlacklist.create!(recipient_canonical: "yes@x.com", scope: "global", source: "manual")
      expect(described_class.blacklisted?(event: event_for(recipient: "yes@x.com"))).to be(true)
    end

    it "false cuando no hay match" do
      expect(described_class.blacklisted?(event: event_for(recipient: "no@x.com"))).to be(false)
    end
  end
end
