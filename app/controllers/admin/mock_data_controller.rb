# frozen_string_literal: true

module Admin
  class MockDataController < Admin::BaseController
    def create
      unless Admin::MockDataFeature.enabled?
        render "errors/forbidden", status: :forbidden
        return
      end

      result = Admin::MockDataGenerator.new.call
      redirect_to request.referer || admin_dashboard_path,
                  notice: "Mock data generado: #{result.rules_seeded} reglas, #{result.audits_added} audits, #{result.queue_items_added} items en cola."
    end

    private

    def controller_section
      :mock_data
    end
  end
end
