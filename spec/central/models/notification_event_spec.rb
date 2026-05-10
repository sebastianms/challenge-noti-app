# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationEvent, type: :model do
  subject(:event) { build(:notification_event) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:notification_type) }
    it { is_expected.to validate_presence_of(:recipient_canonical) }
    it { is_expected.to validate_presence_of(:idempotency_hash) }
    it { is_expected.to validate_presence_of(:idempotency_window_ts) }

    it {
      is_expected.to validate_inclusion_of(:recipient_type)
        .in_array(%w[email user_id])
    }

    it {
      is_expected.to validate_inclusion_of(:status)
        .in_array(%w[pending sent failed rejected])
    }
  end

  describe "scopes" do
    let!(:pending_event)  { create(:notification_event, status: "pending") }
    let!(:sent_event)     { create(:notification_event, :sent, idempotency_hash: SecureRandom.hex) }

    describe ".pending" do
      it "returns only pending events" do
        expect(described_class.pending).to include(pending_event)
        expect(described_class.pending).not_to include(sent_event)
      end
    end
  end

  describe "database constraints" do
    context "when idempotency_hash + idempotency_window_ts is duplicated" do
      let!(:original) { create(:notification_event) }

      it "raises on duplicate insert" do
        duplicate = build(:notification_event,
          idempotency_hash: original.idempotency_hash,
          idempotency_window_ts: original.idempotency_window_ts)

        expect { duplicate.save!(validate: false) }
          .to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    context "when same hash arrives in a different window" do
      let!(:original) { create(:notification_event) }

      it "inserts successfully" do
        next_window = original.idempotency_window_ts + 1.minute
        duplicate_in_new_window = build(:notification_event,
          idempotency_hash: original.idempotency_hash,
          idempotency_window_ts: next_window)

        expect { duplicate_in_new_window.save!(validate: false) }.not_to raise_error
      end
    end

    context "when recipient_type is invalid" do
      it "raises a DB check constraint error" do
        event = build(:notification_event, recipient_type: "sms")

        expect { event.save!(validate: false) }
          .to raise_error(ActiveRecord::StatementInvalid)
      end
    end
  end

  describe "table configuration" do
    it "uses the correct table name" do
      expect(described_class.table_name).to eq("notification_events")
    end
  end
end
