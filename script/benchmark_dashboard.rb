#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark SC-002: Admin::DashboardMetrics#snapshot < 2 s p95 con 10 000 audits.
#
# Uso: docker compose exec app bin/rails runner script/benchmark_dashboard.rb

require "benchmark"

puts "=== Benchmark SC-002: DashboardMetrics#snapshot ==="
puts "Sembrando 10 000 NotificationAudit..."

TYPES    = %w[birthday invoice password_reset promo system_alert].freeze
STATUSES = %w[delivered filtered failed enqueued].freeze

10_000.times do |i|
  NotificationAudit.create!(
    correlation_id:      SecureRandom.uuid,
    status:              STATUSES[i % STATUSES.length],
    channel:             "email",
    source:              "internal",
    notification_type:   TYPES[i % TYPES.length],
    recipient_canonical: "bench#{i}@example.com"
  )
end
puts "  #{NotificationAudit.count} audits en DB."

RUNS = 20
times = []

RUNS.times do
  Rails.cache.clear
  t = Benchmark.realtime { Admin::DashboardMetrics.new.snapshot }
  times << t
end

times_ms = times.map { |t| (t * 1000).round(2) }
sorted    = times_ms.sort
p95       = sorted[(RUNS * 0.95).ceil - 1]
avg       = (times_ms.sum / times_ms.length).round(2)

puts "\n--- Resultados (#{RUNS} runs, cache fría cada vez) ---"
puts "  avg : #{avg} ms"
puts "  min : #{sorted.first} ms"
puts "  p95 : #{p95} ms"
puts "  max : #{sorted.last} ms"
puts ""

TARGET_MS = 2_000
if p95 <= TARGET_MS
  puts "✅ SC-002 PASSED — p95 #{p95} ms ≤ #{TARGET_MS} ms"
else
  puts "❌ SC-002 FAILED — p95 #{p95} ms > #{TARGET_MS} ms"
  exit 1
end
