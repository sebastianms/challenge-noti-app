# frozen_string_literal: true

module Admin
  module NavigationHelper
    def active_section?(section)
      case section
      when :dashboard    then request.path.start_with?(admin_dashboard_path)
      when :rules        then request.path.start_with?(admin_rules_path)
      when :audits       then request.path.start_with?(admin_audits_path)
      when :blacklist_read then request.path.start_with?(admin_blacklist_index_path)
      when :templates    then request.path.start_with?(admin_templates_path)
      when :dlq          then request.path.start_with?(admin_dlq_index_path)
      else false
      end
    end

    def nav_link_to(label, path, section:)
      active = active_section?(section)
      link_to label, path,
        class: "flex items-center px-2 py-1.5 rounded text-sm transition-colors " \
               "#{active ? 'bg-gray-700 text-white font-medium' : 'text-gray-300 hover:bg-gray-800 hover:text-white'}",
        data: { active: active ? "true" : nil }
    end
  end
end
