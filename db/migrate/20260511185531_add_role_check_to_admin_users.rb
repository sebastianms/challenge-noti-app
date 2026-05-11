# frozen_string_literal: true

class AddRoleCheckToAdminUsers < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE admin_users
        ADD CONSTRAINT admin_users_role_chk
        CHECK (role IN ('admin', 'product', 'support', 'engineering'))
    SQL
  end

  def down
    execute "ALTER TABLE admin_users DROP CONSTRAINT admin_users_role_chk"
  end
end
