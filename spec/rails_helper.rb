# frozen_string_literal: true

require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
abort('The Rails environment is running in production mode!') if Rails.env.production?
require 'rspec/rails'
require 'factory_bot_rails'
require 'database_cleaner/active_record'
require 'shoulda/matchers'

Rails.root.glob('spec/support/**/*.rb').sort_by(&:to_s).each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.include ActiveSupport::Testing::TimeHelpers
  config.include Devise::Test::IntegrationHelpers, type: :request

  config.use_transactional_fixtures = false
  config.filter_rails_from_backtrace!
  config.infer_spec_type_from_file_location!

  config.before(:suite) do
    # Eager-load all app code so self-registering initializers (e.g. ChannelRegistry)
    # run regardless of which spec files are included in the run.
    Rails.application.eager_load!
    # Ensure routes are drawn so Devise.mappings is populated before sign_in is called.
    Rails.application.reload_routes!
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    # Thread-based specs (concurrency tests) need truncation strategy
    strategy = example.metadata[:threads] ? :truncation : :transaction
    DatabaseCleaner.strategy = strategy
    DatabaseCleaner.cleaning { example.run }
  end
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
