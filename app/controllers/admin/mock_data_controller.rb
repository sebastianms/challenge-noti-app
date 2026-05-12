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
                  notice: "Mock data generado: #{result.rules_seeded} reglas, #{result.templates_seeded} templates, #{result.blacklist_seeded} blacklist, #{result.audits_added} eventos de auditoría (con timelines), #{result.queue_items_added} items en DLQ."
    end

    private

    def controller_section
      :mock_data
    end
  end
end
