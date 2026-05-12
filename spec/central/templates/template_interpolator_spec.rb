# frozen_string_literal: true

require "rails_helper"

RSpec.describe Templates::TemplateInterpolator do
  describe ".interpolate" do
    it "replaces known variables" do
      out = described_class.interpolate("Hola {{name}}", { name: "Ana" })
      expect(out[:result]).to eq("Hola Ana")
      expect(out[:missing]).to be_empty
    end

    it "reports missing variables and replaces with empty string" do
      out = described_class.interpolate("Hola {{name}}, ID={{user_id}}", { name: "Ana" })
      expect(out[:result]).to eq("Hola Ana, ID=")
      expect(out[:missing]).to contain_exactly("user_id")
    end

    it "returns empty string for empty input" do
      out = described_class.interpolate("", {})
      expect(out[:result]).to eq("")
      expect(out[:missing]).to be_empty
    end

    it "returns string unchanged when no placeholders" do
      out = described_class.interpolate("Sin variables", { name: "Ana" })
      expect(out[:result]).to eq("Sin variables")
      expect(out[:missing]).to be_empty
    end

    it "deduplicates missing keys" do
      out = described_class.interpolate("{{x}} {{x}}", {})
      expect(out[:missing]).to eq([ "x" ])
    end

    it "handles nil input as empty string" do
      out = described_class.interpolate(nil, { name: "Ana" })
      expect(out[:result]).to eq("")
      expect(out[:missing]).to be_empty
    end
  end
end
