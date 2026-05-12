# frozen_string_literal: true

module Admin
  class AuditsController < BaseController
    def controller_section = :audits

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

      respond_to do |format|
        format.html
        format.csv do
          send_data Admin::AuditCsv.generate(@items),
                    filename: "audits-#{Time.zone.now.strftime('%Y%m%d%H%M')}.csv",
                    type: "text/csv; charset=utf-8"
        end
      end
    end

    def show
      timeline = AuditSearch.new(correlation_id: params[:correlation_id]).call
      @timeline = Array(timeline).sort_by(&:created_at)
      @payload  = @timeline.first&.payload
      rule_id   = @timeline.map { |a| a.metadata&.dig("rule_id") }.compact.first
      @rule     = rule_id ? NotificationRule.find_by(id: rule_id) : nil
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
        reason:            params[:reason].presence,
        rule_id:           params[:rule_id].presence,
        notification_type: params[:notification_type].presence,
        page:           (params[:page] || 1).to_i,
        per_page:       (params[:per_page] || AuditSearch::DEFAULT_PER_PAGE).to_i
      }.compact
    end
  end
end
