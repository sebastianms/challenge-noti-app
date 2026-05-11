# frozen_string_literal: true

namespace :worker do
  desc "Run the email Worker in foreground. Args: batch_size (default 10), sleep_interval in seconds (default 5)"
  task :run, [ :batch_size, :sleep_interval ] => :environment do |_, args|
    batch_size     = (args[:batch_size]     || 10).to_i
    sleep_interval = (args[:sleep_interval] || 5).to_i

    Rails.logger.info("Worker starting — batch_size=#{batch_size}, sleep_interval=#{sleep_interval}s")
    Worker.start(batch_size: batch_size, sleep_interval: sleep_interval)
  end
end
