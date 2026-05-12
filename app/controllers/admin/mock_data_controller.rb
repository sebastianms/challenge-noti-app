# frozen_string_literal: true

module Admin
  class MockDataController < Admin::BaseController
    def create
      head :ok
    end

    private

    def controller_section
      :mock_data
    end
  end
end
