# frozen_string_literal: true

require "rails_helper"

# Verifica que las 6 vistas admin rendericen los marcadores de diseño requeridos:
# data-admin-sidebar, admin-table, btn-danger, data-flash-container.
# Implementado como request spec (sin driver de browser) porque Capybara no está configurado.
RSpec.describe "Admin visual consistency", type: :request do
  let(:admin) { create(:admin_user, :admin) }

  before { sign_in admin }

  shared_examples "admin layout markers" do
    it "renders the sidebar marker" do
      expect(response.body).to include("data-admin-sidebar")
    end

    it "renders the flash container marker" do
      expect(response.body).to include("data-flash-container")
    end
  end

  describe "Dashboard" do
    before { get admin_dashboard_path }

    include_examples "admin layout markers"
  end

  describe "Rules index" do
    before { get admin_rules_path }

    include_examples "admin layout markers"

    it "renders the admin-table and btn-danger markers when rules exist" do
      create(:notification_rule)
      get admin_rules_path
      expect(response.body).to include("admin-table")
      expect(response.body).to include("btn-danger")
    end
  end

  describe "Audits index" do
    before { get admin_audits_path }

    include_examples "admin layout markers"

    it "renders the admin-table marker" do
      expect(response.body).to include("admin-table")
    end
  end

  describe "Blacklist index" do
    before { get admin_blacklist_index_path }

    include_examples "admin layout markers"

    it "renders the admin-table and btn-danger markers when entries exist" do
      create(:notification_blacklist)
      get admin_blacklist_index_path
      expect(response.body).to include("admin-table")
      expect(response.body).to include("btn-danger")
    end
  end

  describe "Templates index" do
    before { get admin_templates_path }

    include_examples "admin layout markers"

    it "renders a btn-danger marker when templates exist" do
      create(:notification_template)
      get admin_templates_path
      expect(response.body).to include("btn-danger")
    end
  end

  describe "DLQ index" do
    before { get admin_dlq_index_path }

    include_examples "admin layout markers"

    it "renders the admin-table and btn-danger markers when failed jobs exist" do
      create(:dispatch_queue, :failed)
      get admin_dlq_index_path
      expect(response.body).to include("admin-table")
      expect(response.body).to include("btn-danger")
    end
  end
end
