# frozen_string_literal: true

namespace :bench do
  desc "Synthetic ingestion load test — rake bench:ingestion[rps,duration_seconds]"
  task :ingestion, [ :rps, :duration_seconds ] => :environment do |_, args|
    rps      = (args[:rps] || 50).to_i
    duration = (args[:duration_seconds] || 30).to_i
    total    = rps * duration

    thread_count = [ rps, 32 ].min
    pool_size    = thread_count + 4

    config = ActiveRecord::Base.connection_db_config.configuration_hash
               .except(:pool, :max_connections)
               .merge(max_connections: pool_size)
    ActiveRecord::Base.establish_connection(config)

    bench_class = Class.new(AbstractNotification) do
      notification_type :bench_ingestion
      def self.title(_ctx = {}) = "Bench"
      def self.body(_ctx = {})  = "Bench body"
    end

    puts "Bench: #{total} invocaciones (~#{rps} rps × #{duration}s) | #{thread_count} hilos | pool #{pool_size}"

    # Warmup — establece conexiones antes de medir
    puts "Warmup..."
    [ thread_count, 30 ].min.times do |i|
      bench_class.send("warmup+#{i}@bench.internal", context: { id: i })
    rescue StandardError
      nil
    end

    queue      = Queue.new
    latencies  = []
    errors     = 0
    mutex      = Mutex.new
    done       = false

    # Productores: disparan `rps` tokens por segundo en batches de 10ms
    interval_ms = 10
    per_interval = (rps * interval_ms / 1000.0).ceil
    counter      = 0

    producer = Thread.new do
      until done
        sleep(interval_ms / 1000.0)
        per_interval.times do
          counter += 1
          break if counter > total
          queue << counter
        end
      end
    end

    wall_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    workers = Array.new(thread_count) do
      Thread.new do
        loop do
          idx = queue.pop(true) rescue nil
          if idx.nil?
            break if done
            sleep(0.001)
            next
          end

          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          bench_class.send(
            "bench+#{idx}@bench.internal",
            context: { id: idx, name: "Bench #{idx}" }
          )
          ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000
          mutex.synchronize { latencies << ms }
        rescue => e
          mutex.synchronize { errors += 1 }
        end
      end
    end

    sleep(duration)
    done = true
    producer.join
    workers.each(&:join)

    wall_total = Process.clock_gettime(Process::CLOCK_MONOTONIC) - wall_start

    abort "FAIL: 0 invocaciones completadas (#{errors} errores)" if latencies.empty?

    sorted     = latencies.sort
    p50        = sorted[(sorted.size * 0.50).floor].round(2)
    p95        = sorted[(sorted.size * 0.95).floor].round(2)
    p99        = sorted[(sorted.size * 0.99).floor].round(2)
    actual_rps = (latencies.size.to_f / wall_total).round(1)

    puts ""
    puts "Throughput sostenido:  #{actual_rps} rps"
    puts "Latencia p50:          #{p50} ms"
    puts "Latencia p95:          #{p95} ms"
    puts "Latencia p99:          #{p99} ms"
    puts "Errores:               #{errors}"
    puts "Filas procesadas:      #{latencies.size}"
    puts "Duración real:         #{wall_total.round(1)} s"

    abort "FAIL: p95 #{p95} ms > 50 ms" if p95 > 50
    abort "FAIL: #{errors} errores detectados" if errors > 0
  end
end
