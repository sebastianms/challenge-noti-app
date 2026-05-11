# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    before_action :authenticate_admin_user!
    before_action :authorize_section!

    layout "admin"

    private

    def controller_section
      raise NotImplementedError, "#{self.class} must implement controller_section"
    end

    def authorize_section!
      return if Admin::RoleAuthorizer.allow?(current_admin_user.role, section: controller_section)

      render "errors/forbidden", status: :forbidden
    end
  end
end
