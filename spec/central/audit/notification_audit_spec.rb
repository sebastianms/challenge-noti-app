# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationAudit, type: :model do
  subject(:audit) { build(:notification_audit) }

  describe "validations" do
    it { is_expected.to be_valid }
    it { is_expected.to validate_presence_of(:correlation_id) }
    it { is_expected.to validate_presence_of(:status) }
  end
end
