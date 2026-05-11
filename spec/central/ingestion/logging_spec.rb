# frozen_string_literal: true

require "rails_helper"

RSpec.describe "EventBuilder structured logging", type: :model do
  let(:log_output) { StringIO.new }
  let(:logger)     { ActiveSupport::Logger.new(log_output) }

  before { allow(Rails).to receive(:logger).and_return(logger) }

  def last_log_entry
    log_output.rewind
    lines = log_output.read.split("\n").select { |l| l.include?("notification_ingested") }
    JSON.parse(lines.last)
  end

  it "emits a JSON log on :created" do
    result = BirthdayNotification.send("log@example.com", context: { name: "Log" })

    entry = last_log_entry
    expect(entry["event"]).to eq("notification_ingested")
    expect(entry["state"]).to eq("created")
    expect(entry["correlation_id"]).to eq(result.correlation_id)
    expect(entry["notification_type"]).to eq("birthday")
  end

  it "emits a JSON log on :duplicate with the original correlation_id" do
    r1 = BirthdayNotification.send("dup@example.com", context: { name: "Dup" })
    BirthdayNotification.send("dup@example.com", context: { name: "Dup" })

    entry = last_log_entry
    expect(entry["state"]).to eq("duplicate")
    expect(entry["correlation_id"]).to eq(r1.correlation_id)
  end

  it "does not emit a log entry on :rejected (rejected before persist)" do
    BirthdayNotification.send("", context: { name: "X" })

    log_output.rewind
    lines = log_output.read.split("\n").select { |l| l.include?("notification_ingested") }
    expect(lines).to be_empty
  end
end
