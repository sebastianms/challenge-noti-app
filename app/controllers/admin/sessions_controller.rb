# frozen_string_literal: true

module Admin
  class SessionsController < Devise::SessionsController
    layout "admin"

    protected

    def after_sign_in_path_for(_resource)
      admin_dashboard_path
    end

    def respond_to_on_destroy
      redirect_to new_admin_user_session_path, notice: "Sesión cerrada."
    end
  end
end
