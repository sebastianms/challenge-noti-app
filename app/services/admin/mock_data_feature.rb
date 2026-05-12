# frozen_string_literal: true

module Admin
  module MockDataFeature
    def self.enabled?
      Rails.application.config.allow_mock_data_feature
    end
  end
end
