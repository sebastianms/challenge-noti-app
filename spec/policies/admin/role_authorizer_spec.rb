# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::RoleAuthorizer do
  describe ".allow?" do
    {
      "admin"       => { dashboard: true,  rules: true,  mock_data: true  },
      "product"     => { dashboard: true,  rules: true,  mock_data: false },
      "engineering" => { dashboard: true,  rules: false, mock_data: false },
      "support"     => { dashboard: true,  rules: false, mock_data: false }
    }.each do |role, perms|
      perms.each do |section, allowed|
        it "#{allowed ? "allows" : "denies"} #{role} on :#{section}" do
          expect(described_class.allow?(role, section: section)).to be(allowed)
        end
      end
    end

    it "denies unknown role on any section" do
      expect(described_class.allow?("hacker", section: :dashboard)).to be(false)
    end

    it "denies nil role on any section" do
      expect(described_class.allow?(nil, section: :rules)).to be(false)
    end
  end
end
