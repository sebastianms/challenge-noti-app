# frozen_string_literal: true

require "rails_helper"

RSpec.describe Templates::TemplateResolver do
  before { Rails.cache.clear }

  describe ".title_for" do
    context "when override exists" do
      it "returns interpolated title from DB" do
        create(:notification_template, notification_type: "birthday", title: "¡Feliz día, {{name}}!")
        result = described_class.title_for(type: "birthday", ctx: { name: "Juan" })
        expect(result).to eq("¡Feliz día, Juan!")
      end
    end

    context "when no override exists" do
      it "returns nil" do
        result = described_class.title_for(type: "birthday", ctx: { name: "Juan" })
        expect(result).to be_nil
      end
    end

    context "cache behavior" do
      it "consistently returns the same override on multiple calls" do
        create(:notification_template, notification_type: "promo", title: "Promo {{discount}}%")
        first  = described_class.title_for(type: "promo", ctx: { discount: "10" })
        second = described_class.title_for(type: "promo", ctx: { discount: "10" })
        expect(first).to eq(second)
      end

      it "cache is invalidated after template update" do
        tmpl = create(:notification_template, notification_type: "mfa", title: "Código: {{code}}")
        described_class.title_for(type: "mfa", ctx: { code: "1234" })

        tmpl.update!(title: "Nuevo: {{code}}")
        result = described_class.title_for(type: "mfa", ctx: { code: "5678" })
        expect(result).to eq("Nuevo: 5678")
      end
    end
  end

  describe ".body_for" do
    it "returns interpolated body when override exists" do
      create(:notification_template, notification_type: "birthday", body: "Cuerpo para {{name}}")
      result = described_class.body_for(type: "birthday", ctx: { name: "Ana" })
      expect(result).to eq("Cuerpo para Ana")
    end

    it "returns nil when no override" do
      expect(described_class.body_for(type: "unknown_type", ctx: {})).to be_nil
    end
  end

  describe ".digest_for" do
    it "returns nil when digest_template is nil" do
      create(:notification_template, notification_type: "birthday", digest_template: nil)
      expect(described_class.digest_for(type: "birthday", ctx: {})).to be_nil
    end

    it "returns interpolated digest_template when set" do
      create(:notification_template, notification_type: "birthday", digest_template: "Resumen: {{count}} envíos")
      result = described_class.digest_for(type: "birthday", ctx: { count: "3" })
      expect(result).to eq("Resumen: 3 envíos")
    end
  end
end
