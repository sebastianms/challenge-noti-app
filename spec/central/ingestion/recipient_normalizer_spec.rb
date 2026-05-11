# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecipientNormalizer do
  describe ".normalize" do
    context "con email válido" do
      it "detecta tipo :email" do
        result = described_class.normalize("JUAN@example.com")
        expect(result[:type]).to eq(:email)
      end

      it "normaliza a lowercase" do
        result = described_class.normalize("JUAN@EXAMPLE.COM")
        expect(result[:canonical]).to eq("juan@example.com")
      end

      it "elimina espacios extremos" do
        result = described_class.normalize("  user@example.com  ")
        expect(result[:canonical]).to eq("user@example.com")
      end
    end

    context "con user_id válido" do
      it "detecta tipo :user_id" do
        result = described_class.normalize("usr_abc123")
        expect(result[:type]).to eq(:user_id)
      end

      it "normaliza a lowercase" do
        result = described_class.normalize("USR_ABC123")
        expect(result[:canonical]).to eq("usr_abc123")
      end
    end

    context "con inputs inválidos" do
      it "lanza ArgumentError cuando está vacío" do
        expect { described_class.normalize("") }
          .to raise_error(ArgumentError, /blank/)
      end

      it "lanza ArgumentError cuando es nil" do
        expect { described_class.normalize(nil) }
          .to raise_error(ArgumentError, /blank/)
      end

      it "lanza ArgumentError cuando contiene salto de línea" do
        expect { described_class.normalize("juan\nattacker@x.com") }
          .to raise_error(ArgumentError, /invalid characters/)
      end

      it "lanza ArgumentError cuando contiene retorno de carro" do
        expect { described_class.normalize("juan\rattacker") }
          .to raise_error(ArgumentError, /invalid characters/)
      end

      it "lanza ArgumentError cuando supera 320 caracteres" do
        long = "a" * 321
        expect { described_class.normalize(long) }
          .to raise_error(ArgumentError, /exceeds/)
      end

      it "acepta exactamente 320 caracteres" do
        edge = "a" * 320
        expect { described_class.normalize(edge) }.not_to raise_error
      end
    end
  end
end
