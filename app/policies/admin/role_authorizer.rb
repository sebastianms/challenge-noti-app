# frozen_string_literal: true

module Admin
  class RoleAuthorizer
    PERMISSIONS = {
      "admin"       => %i[dashboard rules mock_data audits blacklist_read blacklist_write].freeze,
      "product"     => %i[dashboard rules audits blacklist_read].freeze,
      "engineering" => %i[dashboard audits blacklist_read].freeze,
      "support"     => %i[dashboard audits blacklist_read blacklist_write].freeze
    }.freeze

    def self.allow?(role, section:)
      PERMISSIONS.fetch(role.to_s, []).include?(section)
    end
  end
end
