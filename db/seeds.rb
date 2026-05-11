# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

if Rails.env.development? || Rails.env.test?
  [
    { email: "admin@noti-central.local",       role: "admin" },
    { email: "product@noti-central.local",     role: "product" },
    { email: "support@noti-central.local",     role: "support" },
    { email: "engineering@noti-central.local", role: "engineering" }
  ].each do |attrs|
    next if AdminUser.exists?(email: attrs[:email])

    AdminUser.create!(attrs.merge(password: "Admin12345678!", password_confirmation: "Admin12345678!"))
    puts "  [seed] AdminUser created: #{attrs[:email]} (#{attrs[:role]})"
  end
end
