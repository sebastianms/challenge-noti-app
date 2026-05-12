# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::NavigationHelper, type: :helper do
  let(:admin_user) { build_stubbed(:admin_user, role: "admin") }

  before { allow(helper).to receive(:current_admin_user).and_return(admin_user) }

  describe "#active_section?" do
    it "returns true when path matches section" do
      allow(helper.request).to receive(:path).and_return("/admin/dashboard")
      expect(helper.active_section?(:dashboard)).to be true
    end

    it "returns false when path does not match section" do
      allow(helper.request).to receive(:path).and_return("/admin/rules")
      expect(helper.active_section?(:dashboard)).to be false
    end

    it "returns true for nested paths under a section" do
      allow(helper.request).to receive(:path).and_return("/admin/rules/1/edit")
      expect(helper.active_section?(:rules)).to be true
    end

    it "returns false for unknown sections" do
      allow(helper.request).to receive(:path).and_return("/admin/dashboard")
      expect(helper.active_section?(:unknown)).to be false
    end

    it "detects audits section" do
      allow(helper.request).to receive(:path).and_return("/admin/audits")
      expect(helper.active_section?(:audits)).to be true
    end

    it "detects dlq section" do
      allow(helper.request).to receive(:path).and_return("/admin/dlq")
      expect(helper.active_section?(:dlq)).to be true
    end

    it "detects blacklist_read section" do
      allow(helper.request).to receive(:path).and_return("/admin/blacklist")
      expect(helper.active_section?(:blacklist_read)).to be true
    end

    it "detects templates section" do
      allow(helper.request).to receive(:path).and_return("/admin/templates")
      expect(helper.active_section?(:templates)).to be true
    end
  end

  describe "#nav_link_to" do
    before { allow(helper.request).to receive(:path).and_return("/admin/dashboard") }

    it "renders a link with active data attribute when section matches" do
      html = helper.nav_link_to("Dashboard", "/admin/dashboard", section: :dashboard)
      expect(html).to include('data-active="true"')
    end

    it "renders a link without active data attribute when section does not match" do
      html = helper.nav_link_to("Reglas", "/admin/rules", section: :rules)
      expect(html).not_to include("data-active")
    end

    it "applies active styling class when section matches" do
      html = helper.nav_link_to("Dashboard", "/admin/dashboard", section: :dashboard)
      expect(html).to include("bg-gray-700")
    end

    it "applies inactive styling class when section does not match" do
      html = helper.nav_link_to("Reglas", "/admin/rules", section: :rules)
      expect(html).to include("text-gray-300")
    end
  end
end
