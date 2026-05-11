# frozen_string_literal: true

module Admin
  class RoleAuthorizer
    PERMISSIONS = {
      "admin"       => %i[dashboard rules mock_data].freeze,
      "product"     => %i[dashboard rules].freeze,
      "engineering" => %i[dashboard].freeze,
      "support"     => %i[dashboard].freeze
    }.freeze

    def self.allow?(role, section:)
      PERMISSIONS.fetch(role.to_s, []).include?(section)
    end
  end
end
