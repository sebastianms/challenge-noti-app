# frozen_string_literal: true

require "rails_helper"

RSpec.describe AbstractNotification do
  describe "subclase con title y body" do
    it "carga sin errores" do
      expect { BirthdayNotification }.not_to raise_error
    end
  end

  describe "subclase sin title" do
    it "lanza NotImplementedError con mensaje específico al invocar title" do
      expect { BrokenNotification.title }
        .to raise_error(NotImplementedError, /BrokenNotification must implement self\.title/)
    end
  end

  describe "subclase sin body" do
    it "lanza NotImplementedError con mensaje específico al invocar body" do
      expect { BrokenNotification.body }
        .to raise_error(NotImplementedError, /BrokenNotification must implement self\.body/)
    end
  end

  describe ".resolved_notification_type" do
    context "cuando se declara notification_type" do
      it "retorna el identificador declarado" do
        expect(BirthdayNotification.resolved_notification_type).to eq("birthday")
      end
    end

    context "cuando no se declara notification_type" do
      it "retorna el FQN normalizado sin sufijo _notification" do
        klass = Class.new(AbstractNotification) do
          def self.name = "SomeAlertNotification"

          def self.title(_ctx = {}) = "t"
          def self.body(_ctx = {}) = "b"
        end
        expect(klass.resolved_notification_type).to eq("some_alert")
      end
    end
  end

  describe ".resolved_idempotency_window" do
    context "cuando se declara idempotency_window" do
      it "retorna la duración declarada" do
        expect(InvoicePaidNotification.resolved_idempotency_window).to eq(1.hour)
      end
    end

    context "cuando no se declara idempotency_window" do
      it "retorna 1 minuto por defecto" do
        expect(BirthdayNotification.resolved_idempotency_window).to eq(1.minute)
      end
    end
  end
end
