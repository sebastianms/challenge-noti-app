# frozen_string_literal: true

namespace :webhook_worker do
  desc "Run the WebhookEventWorker in foreground. Usage: rake 'webhook_worker:run[batch_size,sleep_interval]'"
  task :run, [ :batch_size, :sleep_interval ] => :environment do |_t, args|
    batch_size     = (args[:batch_size]     || 10).to_i
    sleep_interval = (args[:sleep_interval] || 5).to_i
    puts "WebhookEventWorker starting (batch_size=#{batch_size}, sleep_interval=#{sleep_interval}s)"
    WebhookEventWorker.start(batch_size: batch_size, sleep_interval: sleep_interval)
  end
end
