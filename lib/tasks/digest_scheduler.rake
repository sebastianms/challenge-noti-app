# frozen_string_literal: true

namespace :digest_scheduler do
  desc "Run the DigestScheduler in foreground. Usage: rake 'digest_scheduler:run[batch_size,sleep_interval]'"
  task :run, [ :batch_size, :sleep_interval ] => :environment do |_t, args|
    batch_size     = (args[:batch_size]     || ENV.fetch("DIGEST_SCHEDULER_BATCH_SIZE", 50)).to_i
    sleep_interval = (args[:sleep_interval] || ENV.fetch("DIGEST_SCHEDULER_SLEEP_INTERVAL", 60)).to_i
    puts "DigestScheduler starting (batch_size=#{batch_size}, sleep_interval=#{sleep_interval}s)"
    DigestScheduler.start(batch_size: batch_size, sleep_interval: sleep_interval)
  end
end
