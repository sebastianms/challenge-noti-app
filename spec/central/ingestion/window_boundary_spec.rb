# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Borde de ventana de idempotencia" do
  it "invocaciones en ventanas distintas crean dos filas (comportamiento documentado)" do
    travel_to Time.utc(2026, 5, 10, 10, 23, 59) do
      BirthdayNotification.send("juan@x.com", context: { invoice: 42 })
    end

    travel_to Time.utc(2026, 5, 10, 10, 24, 1) do
      BirthdayNotification.send("juan@x.com", context: { invoice: 42 })
    end

    expect(NotificationEvent.where(notification_type: "birthday").count).to eq(2)
  end

  it "invocaciones en la misma ventana producen una sola fila" do
    travel_to Time.utc(2026, 5, 10, 10, 23, 0) do
      BirthdayNotification.send("juan@x.com", context: { invoice: 42 })
    end

    travel_to Time.utc(2026, 5, 10, 10, 23, 59) do
      BirthdayNotification.send("juan@x.com", context: { invoice: 42 })
    end

    expect(NotificationEvent.where(notification_type: "birthday").count).to eq(1)
  end
end
