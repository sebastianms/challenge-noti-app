# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventBuilder, type: :model do
  describe ".build" do
    context "inputs válidos sin context" do
      it "retorna :created con correlation_id UUID" do
        result = BirthdayNotification.send("juan@example.com")

        expect(result).to be_created
        expect(result.correlation_id).to match(/\A[\da-f-]{36}\z/)
      end

      it "persiste exactamente una fila" do
        BirthdayNotification.send("juan@example.com")
        expect(NotificationEvent.count).to eq(1)
      end
    end

    context "segunda invocación equivalente dentro de la ventana" do
      it "retorna :duplicate con el mismo correlation_id" do
        r1 = BirthdayNotification.send("juan@example.com")
        r2 = BirthdayNotification.send("juan@example.com")

        expect(r2).to be_duplicate
        expect(r2.correlation_id).to eq(r1.correlation_id)
      end

      it "no crea una segunda fila" do
        BirthdayNotification.send("juan@example.com")
        BirthdayNotification.send("juan@example.com")
        expect(NotificationEvent.count).to eq(1)
      end
    end

    context "context distinto produce evento separado" do
      it "retorna dos :created con correlation_ids distintos" do
        r1 = BirthdayNotification.send("juan@example.com", context: { id: 1 })
        r2 = BirthdayNotification.send("juan@example.com", context: { id: 2 })

        expect(r1).to be_created
        expect(r2).to be_created
        expect(r1.correlation_id).not_to eq(r2.correlation_id)
      end
    end

    context "recipient inválido" do
      it "retorna :rejected sin crear fila" do
        result = BirthdayNotification.send("")

        expect(result).to be_rejected
        expect(result.reason).to match(/blank/)
        expect(NotificationEvent.count).to eq(0)
      end
    end

    context "payload no serializable" do
      it "retorna :rejected sin crear fila" do
        result = BirthdayNotification.send("juan@example.com", context: { obj: BasicObject.new })

        expect(result).to be_rejected
        expect(NotificationEvent.count).to eq(0)
      end
    end

    context "enqueue tras persistencia" do
      it "crea un job en dispatch_queue cuando el evento es nuevo" do
        BirthdayNotification.send("juan@example.com")
        expect(DispatchQueue.count).to eq(1)
        expect(DispatchQueue.last.status).to eq("pending")
      end

      it "no crea job adicional cuando el evento es duplicado" do
        BirthdayNotification.send("juan@example.com")
        BirthdayNotification.send("juan@example.com")
        expect(DispatchQueue.count).to eq(1)
      end
    end
  end
end
