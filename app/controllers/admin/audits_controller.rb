# frozen_string_literal: true

module Admin
  class AuditsController < ApplicationController
    http_basic_authenticate_with(
      name:     ENV.fetch("AUDIT_BASIC_AUTH_USER", "admin"),
      password: ENV.fetch("AUDIT_BASIC_AUTH_PASSWORD", "admin")
    )

    def index
      @filters = filter_params
      @search  = AuditSearch.new(**@filters).call

      if @search.is_a?(Array)
        @items    = @search
        @total    = @search.size
        @page     = 1
        @per_page = @items.size
        @has_next = false
      else
        @items    = @search.items
        @total    = @search.total
        @page     = @search.page
        @per_page = @search.per_page
        @has_next = @search.has_next?
      end
    end

    private

    def filter_params
      {
        correlation_id: params[:correlation_id].presence,
        recipient:      params[:recipient].presence,
        status:         params[:status].presence,
        source:         params[:source].presence,
        from:           params[:from].presence,
        to:             params[:to].presence,
        page:           (params[:page] || 1).to_i,
        per_page:       (params[:per_page] || AuditSearch::DEFAULT_PER_PAGE).to_i
      }.compact
    end
  end
end
