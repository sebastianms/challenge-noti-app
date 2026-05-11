# frozen_string_literal: true

Rails.application.config.allow_mock_data_feature = ENV.fetch("ALLOW_MOCK_DATA_FEATURE", "true") != "false"
