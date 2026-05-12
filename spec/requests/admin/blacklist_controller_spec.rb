# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::BlacklistController", type: :request do
  let(:admin)   { create(:admin_user, :admin) }
  let(:support) { create(:admin_user, :support) }

  describe "GET /admin/blacklist" do
    it "redirects to login when unauthenticated" do
      get admin_blacklist_index_path
      expect(response).to redirect_to(new_admin_user_session_path)
    end

    it "returns 200 for support role" do
      sign_in support
      get admin_blacklist_index_path
      expect(response).to have_http_status(:ok)
    end

    context "CSV export" do
      before { sign_in admin }

      it "returns text/csv with blacklist data" do
        create(:notification_blacklist, recipient_canonical: "csv@test.com", reason: "GDPR")

        get admin_blacklist_index_path(format: :csv)

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("text/csv")
        expect(response.body).to include("recipient_canonical")
        expect(response.body).to include("csv@test.com")
        expect(response.body).to include("GDPR")
      end

      it "returns only header for empty result" do
        get admin_blacklist_index_path(format: :csv, params: { recipient: "nobody@example.com" })

        expect(response.body.lines.size).to eq(1)
        expect(response.body).to include("id,recipient_canonical")
      end
    end
  end

  describe "DELETE /admin/blacklist/:id" do
    before { sign_in admin }

    it "records removed_by as admin email" do
      entry = create(:notification_blacklist)

      delete admin_blacklist_path(entry)

      audit = NotificationAudit.where(notification_type: "_blacklist_removed_").last
      expect(audit.metadata["removed_by"]).to eq(admin.email)
    end

    it "destroys the entry" do
      entry = create(:notification_blacklist)

      delete admin_blacklist_path(entry)

      expect(NotificationBlacklist.exists?(entry.id)).to be false
    end
  end

  describe "POST /admin/blacklist" do
    it "returns 403 for engineering role" do
      engineering = create(:admin_user, :engineering)
      sign_in engineering

      post admin_blacklist_index_path, params: { recipient: "x@example.com", scope: "global" }

      expect(response).to have_http_status(:forbidden)
    end

    it "creates a blacklist entry for support" do
      sign_in support

      post admin_blacklist_index_path, params: {
        recipient: "blocked@example.com", scope: "global", reason: "GDPR ticket #1"
      }

      expect(response).to redirect_to(admin_blacklist_index_path)
      expect(NotificationBlacklist.find_by(recipient_canonical: "blocked@example.com")).to be_present
    end
  end
end
