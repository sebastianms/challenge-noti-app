# frozen_string_literal: true

require "rails_helper"

RSpec.describe SendResult do
  describe "estados válidos" do
    it "acepta :created" do
      expect { described_class.created(correlation_id: "uuid-1") }.not_to raise_error
    end

    it "acepta :duplicate" do
      expect { described_class.duplicate(correlation_id: "uuid-1") }.not_to raise_error
    end

    it "acepta :rejected" do
      expect { described_class.rejected(reason: "blank") }.not_to raise_error
    end

    it "rechaza estado inválido" do
      expect { described_class.new(state: :unknown) }.to raise_error(ArgumentError, /invalid state/)
    end
  end

  describe "frozen" do
    it "está congelado luego de construirse" do
      result = described_class.created(correlation_id: "uuid-1")
      expect(result).to be_frozen
    end
  end

  describe "métodos predicado" do
    let(:created)   { described_class.created(correlation_id: "uuid-1") }
    let(:duplicate) { described_class.duplicate(correlation_id: "uuid-1") }
    let(:rejected)  { described_class.rejected(reason: "bad input") }

    it { expect(created).to be_created }
    it { expect(created).not_to be_duplicate }
    it { expect(created).not_to be_rejected }
    it { expect(created).to be_persisted }

    it { expect(duplicate).to be_duplicate }
    it { expect(duplicate).to be_persisted }

    it { expect(rejected).to be_rejected }
    it { expect(rejected).not_to be_persisted }
  end

  describe "#to_h" do
    it "serializa :created con correlation_id" do
      result = described_class.created(correlation_id: "abc-123")
      expect(result.to_h).to eq({ state: :created, correlation_id: "abc-123" })
    end

    it "serializa :rejected con reason sin correlation_id" do
      result = described_class.rejected(reason: "blank recipient")
      expect(result.to_h).to eq({ state: :rejected, reason: "blank recipient" })
    end
  end

  describe ":rejected no devuelve correlation_id" do
    it "correlation_id es nil" do
      result = described_class.rejected(reason: "blank")
      expect(result.correlation_id).to be_nil
    end
  end
end
