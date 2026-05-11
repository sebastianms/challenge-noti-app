require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ChallengeNotiApp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Central de Notificaciones custom directories
    config.autoload_paths += %W[
      #{config.root}/app/notifications
      #{config.root}/app/central
      #{config.root}/app/central/models
      #{config.root}/app/central/ingestion
      #{config.root}/app/central/broker
      #{config.root}/app/central/broker/digests
      #{config.root}/app/central/channels
      #{config.root}/app/central/audit
      #{config.root}/app/central/webhooks
      #{config.root}/app/central/decisioning
    ]
    config.eager_load_paths += %W[
      #{config.root}/app/notifications
      #{config.root}/app/central
      #{config.root}/app/central/models
      #{config.root}/app/central/ingestion
      #{config.root}/app/central/broker
      #{config.root}/app/central/broker/digests
      #{config.root}/app/central/channels
      #{config.root}/app/central/audit
      #{config.root}/app/central/webhooks
      #{config.root}/app/central/decisioning
    ]

    config.time_zone = "UTC"
    config.generators.system_tests = nil

    # Postgres partitioned tables require SQL format (schema.rb can't represent PARTITION BY RANGE)
    config.active_record.schema_format = :sql
  end
end
