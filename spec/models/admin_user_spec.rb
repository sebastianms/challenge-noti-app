# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdminUser, type: :model do
  it "is valid with valid attributes" do
    expect(build(:admin_user)).to be_valid
  end

  describe "role validation" do
    %w[admin product support engineering].each do |role|
      it "accepts role #{role}" do
        expect(build(:admin_user, role: role)).to be_valid
      end
    end

    it "rejects unknown role" do
      expect(build(:admin_user, role: "superuser")).not_to be_valid
    end

    it "rejects blank role" do
      expect(build(:admin_user, role: "")).not_to be_valid
    end
  end

  describe "email validation" do
    it "requires unique email" do
      create(:admin_user, email: "dup@example.com")
      expect(build(:admin_user, email: "dup@example.com")).not_to be_valid
    end

    it "rejects blank email" do
      expect(build(:admin_user, email: "")).not_to be_valid
    end
  end

  describe "password validation" do
    it "rejects password shorter than 12 characters" do
      expect(build(:admin_user, password: "Short1!", password_confirmation: "Short1!")).not_to be_valid
    end

    it "accepts password of 12+ characters" do
      expect(build(:admin_user, password: "LongEnough12!", password_confirmation: "LongEnough12!")).to be_valid
    end
  end
end
