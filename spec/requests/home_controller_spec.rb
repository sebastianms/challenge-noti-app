# frozen_string_literal: true

require "rails_helper"
require "benchmark"

RSpec.describe "Home", type: :request do
  describe "GET /" do
    context "without a session" do
      it "returns 200" do
        get root_path
        expect(response).to have_http_status(:ok)
      end

      it "does not redirect" do
        get root_path
        expect(response).not_to be_redirect
      end

      it "renders the sign-in CTA" do
        get root_path
        expect(response.body).to include("Ingresar")
      end

      it "responds in under 100ms", :aggregate_failures do
        elapsed = Benchmark.realtime { get root_path }
        expect(response).to have_http_status(:ok)
        expect(elapsed).to be < 0.1
      end
    end

    context "with an authenticated admin session" do
      let(:admin) { create(:admin_user) }

      before { sign_in admin }

      it "returns 200" do
        get root_path
        expect(response).to have_http_status(:ok)
      end

      it "does not redirect" do
        get root_path
        expect(response).not_to be_redirect
      end

      it "renders the dashboard CTA instead of sign-in" do
        get root_path
        expect(response.body).to include("Ir al panel")
        expect(response.body).not_to include("Ingresar")
      end
    end
  end
end
