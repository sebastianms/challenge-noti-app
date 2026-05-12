# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationTemplate, type: :model do
  subject(:template) { build(:notification_template) }

  describe "validations" do
    it { is_expected.to be_valid }
    it { is_expected.to validate_presence_of(:notification_type) }
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:body) }
    it { is_expected.to validate_presence_of(:locale) }

    it "rejects invalid notification_type format" do
      template.notification_type = "Birthday-Type"
      expect(template).not_to be_valid
      expect(template.errors[:notification_type]).to be_present
    end

    it "rejects title longer than 2000 chars" do
      template.title = "a" * 2001
      expect(template).not_to be_valid
    end

    it "accepts nil digest_template" do
      template.digest_template = nil
      expect(template).to be_valid
    end

    it "rejects digest_template longer than 4000 chars" do
      template.digest_template = "a" * 4001
      expect(template).not_to be_valid
    end
  end

  describe "uniqueness constraint" do
    it "rejects duplicate (notification_type, locale)" do
      create(:notification_template, notification_type: "promo", locale: "es")
      duplicate = build(:notification_template, notification_type: "promo", locale: "es")
      expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "cache invalidation callbacks" do
    it "calls TemplateCache.invalidate after save" do
      allow(Templates::TemplateCache).to receive(:invalidate)
      template.save!
      expect(Templates::TemplateCache).to have_received(:invalidate).with("birthday", "es")
    end

    it "calls TemplateCache.invalidate after destroy" do
      template.save!
      allow(Templates::TemplateCache).to receive(:invalidate)
      template.destroy!
      expect(Templates::TemplateCache).to have_received(:invalidate).with("birthday", "es")
    end
  end
end
