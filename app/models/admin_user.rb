# frozen_string_literal: true

class AdminUser < ApplicationRecord
  devise :database_authenticatable, :rememberable, :validatable,
         :trackable, :lockable, :recoverable

  ROLES = %w[admin product support engineering].freeze

  validates :role, inclusion: { in: ROLES }
end
