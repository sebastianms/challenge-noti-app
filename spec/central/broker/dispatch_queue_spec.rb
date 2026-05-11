# frozen_string_literal: true

require "rails_helper"

RSpec.describe DispatchQueue, type: :model do
  subject(:job) { build(:dispatch_queue) }

  describe "validations" do
    it { is_expected.to be_valid }
    it { is_expected.to validate_presence_of(:event_id) }
    it { is_expected.to validate_inclusion_of(:priority).in_array(%w[critical standard bulk]) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[pending in_flight done failed]) }
  end

  describe "#next_backoff" do
    it "returns 1 minute on first attempt" do
      job.attempts = 0
      expect(job.next_backoff).to eq(1.minute)
    end

    it "returns 5 minutes on second attempt" do
      job.attempts = 1
      expect(job.next_backoff).to eq(5.minutes)
    end

    it "returns 25 minutes on third attempt" do
      job.attempts = 2
      expect(job.next_backoff).to eq(25.minutes)
    end

    it "caps at last value when attempts exceed schedule" do
      job.attempts = 99
      expect(job.next_backoff).to eq(25.minutes)
    end
  end

  describe "#permanent_failure?" do
    it "is false below MAX_ATTEMPTS" do
      job.attempts = DispatchQueue::MAX_ATTEMPTS - 1
      expect(job.permanent_failure?).to be false
    end

    it "is true at MAX_ATTEMPTS" do
      job.attempts = DispatchQueue::MAX_ATTEMPTS
      expect(job.permanent_failure?).to be true
    end
  end
end
