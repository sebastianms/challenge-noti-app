# frozen_string_literal: true

module LoadTestAuth
  USER     = ENV["LOAD_TEST_BASIC_AUTH_USER"]
  PASSWORD = ENV["LOAD_TEST_BASIC_AUTH_PASSWORD"]
  ENABLED  = ENV["ALLOW_LOAD_TEST_INGEST"] == "1" && USER.present? && PASSWORD.present?
end
