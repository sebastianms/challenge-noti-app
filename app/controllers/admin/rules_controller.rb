# frozen_string_literal: true

module Admin
  class RulesController < Admin::BaseController
    def index
      head :ok
    end

    private

    def controller_section
      :rules
    end
  end
end
