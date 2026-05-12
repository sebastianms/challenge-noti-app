# frozen_string_literal: true

module Admin
  class DashboardController < Admin::BaseController
    def index
      head :ok
    end

    private

    def controller_section
      :dashboard
    end
  end
end
