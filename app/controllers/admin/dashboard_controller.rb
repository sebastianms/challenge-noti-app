# frozen_string_literal: true

module Admin
  class DashboardController < Admin::BaseController
    def index
      @snapshot = Admin::DashboardMetrics.new.snapshot
    end

    private

    def controller_section
      :dashboard
    end
  end
end
