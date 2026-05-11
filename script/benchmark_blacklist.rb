# frozen_string_literal: true

# Smoke benchmark de SC-005 (005-blacklist-bounces):
# p95 de BlacklistEvaluator.match con 100k filas seedadas debe ser ≤ 5 ms.

require "benchmark"
require "ostruct"

ROW_COUNT     = 100_000
LOOKUP_COUNT  = 1_000
TARGET_P95_MS = 5.0

puts "[bench] seeding #{ROW_COUNT} filas de blacklist..."
NotificationBlacklist.where("recipient_canonical LIKE 'user%@bench.x'").delete_all
ROW_COUNT.times.each_slice(1_000) do |slice|
  rows = slice.map { |i| { recipient_canonical: "user#{i}@bench.x", scope: "global", source: "manual" } }
  NotificationBlacklist.insert_all(rows)
end

puts "[bench] midiendo #{LOOKUP_COUNT} lookups..."
times_ms = Array.new(LOOKUP_COUNT) do
  event = OpenStruct.new(recipient_canonical: "user#{rand(ROW_COUNT)}@bench.x", notification_type: "birthday")
  Benchmark.realtime { BlacklistEvaluator.match(event: event) } * 1_000
end

sorted = times_ms.sort
p95    = sorted[(sorted.size * 0.95).to_i]
avg    = sorted.sum / sorted.size

puts "[bench] avg = #{avg.round(3)} ms · p95 = #{p95.round(3)} ms · target ≤ #{TARGET_P95_MS} ms"
abort "[bench] FAIL: p95 #{p95.round(3)} ms > target #{TARGET_P95_MS} ms" if p95 > TARGET_P95_MS

puts "[bench] PASS"
