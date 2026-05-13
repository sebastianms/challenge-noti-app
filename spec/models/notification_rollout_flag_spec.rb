# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationRolloutFlag, type: :model do
  describe "validations" do
    it "is valid with notification_type, team_name and enrolled" do
      flag = build(:notification_rollout_flag)
      expect(flag).to be_valid
    end

    it "requires notification_type" do
      expect(build(:notification_rollout_flag, notification_type: nil)).not_to be_valid
    end

    it "requires team_name" do
      expect(build(:notification_rollout_flag, team_name: nil)).not_to be_valid
    end

    it "enforces uniqueness on notification_type" do
      create(:notification_rollout_flag, notification_type: "password_reset")
      expect(build(:notification_rollout_flag, notification_type: "password_reset")).not_to be_valid
    end
  end

  describe ".enrolled?" do
    it "returns true when no flag exists for the type" do
      expect(described_class.enrolled?("unknown_type")).to be true
    end

    it "returns true when the flag is enrolled" do
      create(:notification_rollout_flag, notification_type: "welcome_email", enrolled: true)
      expect(described_class.enrolled?("welcome_email")).to be true
    end

    it "returns false when the flag is not enrolled" do
      create(:notification_rollout_flag, notification_type: "promo_weekend", enrolled: false)
      expect(described_class.enrolled?("promo_weekend")).to be false
    end
  end

  describe "scopes" do
    before do
      create(:notification_rollout_flag, notification_type: "a", enrolled: true)
      create(:notification_rollout_flag, notification_type: "b", enrolled: false)
    end

    it ".enrolled returns only enrolled flags" do
      expect(described_class.enrolled.count).to eq(1)
    end

    it ".not_enrolled returns only inactive flags" do
      expect(described_class.not_enrolled.count).to eq(1)
    end
  end
end
