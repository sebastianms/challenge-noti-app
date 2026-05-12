# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::BlacklistController, type: :request do
  let(:admin) { create(:admin_user, :admin) }

  before { sign_in admin }

  describe "GET /admin/blacklist" do
    it "redirige a login sin sesión" do
      sign_out admin
      get "/admin/blacklist"
      expect(response).to redirect_to(new_admin_user_session_path)
    end

    it "200 con sesión y muestra filas" do
      create(:notification_blacklist, recipient_canonical: "a@x.com")
      get "/admin/blacklist"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("a@x.com")
    end

    it "filtra por scope=channel" do
      create(:notification_blacklist, :global,         recipient_canonical: "g@x.com")
      create(:notification_blacklist, :channel_scoped, recipient_canonical: "c@x.com")
      get "/admin/blacklist", params: { scope: "channel" }
      expect(response.body).to include("c@x.com")
      expect(response.body).not_to include("g@x.com")
    end
  end

  describe "POST /admin/blacklist" do
    it "302 + fila creada con source=admin_ui" do
      post "/admin/blacklist",
           params: { recipient: "New@Example.com", scope: "global", reason: "ticket #1" }
      expect(response).to have_http_status(:see_other)

      entry = NotificationBlacklist.last
      expect(entry.recipient_canonical).to eq("new@example.com")
      expect(entry.source).to eq("admin_ui")
    end

    it "422 cuando scope=type sin target (CHECK constraint)" do
      post "/admin/blacklist",
           params: { recipient: "bad@example.com", scope: "type", target: "", reason: "x" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(NotificationBlacklist.where(recipient_canonical: "bad@example.com")).to be_empty
    end

    it "redirige con flash error cuando el recipient es inválido" do
      post "/admin/blacklist",
           params: { recipient: "", scope: "global" }
      expect(response).to have_http_status(:see_other)
      expect(flash[:error]).to eq("Recipient inválido")
      expect(NotificationBlacklist.count).to eq(0)
    end
  end

  describe "DELETE /admin/blacklist/:id" do
    it "302 + fila borrada + audit blacklist_removed con removed_by=email y reason" do
      entry = create(:notification_blacklist, recipient_canonical: "del@example.com")

      delete "/admin/blacklist/#{entry.id}",
             params: { reason: "user reactivated" }
      expect(response).to have_http_status(:see_other)
      expect(NotificationBlacklist.find_by(id: entry.id)).to be_nil

      audit = NotificationAudit.where(notification_type: "_blacklist_removed_").last
      expect(audit.status).to eq("blacklist_removed")
      expect(audit.metadata["blacklist_id"]).to eq(entry.id)
      expect(audit.metadata["removed_by"]).to eq(admin.email)
      expect(audit.metadata["reason"]).to eq("user reactivated")
    end

    it "404 cuando el id no existe" do
      delete "/admin/blacklist/999999"
      expect(response).to have_http_status(:not_found)
    end
  end
end
