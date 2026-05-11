# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Idempotencia bajo concurrencia", :threads do
  # Libera conexiones retenidas por tests anteriores para que los 50 hilos
  # no agoten el pool al competir contra conexiones del thread principal.
  before { ActiveRecord::Base.connection_pool.disconnect! }

  it "produce exactamente una fila bajo 10k invocaciones simultáneas" do
    threads_count = 50
    per_thread    = 200
    results       = Concurrent::Array.new

    # Congela el tiempo para que todos los threads calculen el mismo window_ts.
    # Sin freeze_time, si el test cruza un límite de minuto (idempotency_window=1.minute),
    # threads en minutos distintos generan hashes distintos y pasan el ON CONFLICT DO NOTHING.
    freeze_time

    workers = threads_count.times.map do
      Thread.new do
        per_thread.times do
          results << BirthdayNotification.send("juan@example.com", context: { invoice: 42 })
        end
      end
    end
    workers.each(&:join)

    rows = NotificationEvent.where(
      notification_type:   "birthday",
      recipient_canonical: "juan@example.com",
      context_id:          "42"
    ).count

    created_count   = results.count(&:created?)
    duplicate_count = results.count(&:duplicate?)

    expect(rows).to eq(1)
    expect(created_count).to eq(1)
    expect(duplicate_count).to eq(threads_count * per_thread - 1)
    expect(results.count(&:rejected?)).to eq(0)
  end
end
