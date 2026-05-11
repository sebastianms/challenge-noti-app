# frozen_string_literal: true

module Admin
  class BlacklistController < ApplicationController
    PER_PAGE = 50

    http_basic_authenticate_with(
      name:     ENV.fetch("AUDIT_BASIC_AUTH_USER", "admin"),
      password: ENV.fetch("AUDIT_BASIC_AUTH_PASSWORD", "admin")
    )

    def index
      @filters = filter_params
      @items   = build_query(@filters).limit(PER_PAGE)
      @total   = build_query(@filters).count
    end

    def create
      canonical = canonicalize(params[:recipient])
      if canonical.blank?
        flash[:error] = "Recipient inválido"
        redirect_to(admin_blacklist_index_path, status: :see_other) and return
      end

      NotificationBlacklist.create!(
        recipient_canonical: canonical,
        scope:               params[:scope],
        target:              params[:target].presence,
        source:              "admin_ui",
        reason:              params[:reason]
      )
      redirect_to admin_blacklist_index_path, status: :see_other
    rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid => e
      flash[:error] = e.message
      redirect_to admin_blacklist_index_path, status: :unprocessable_entity
    end

    def destroy
      entry = NotificationBlacklist.find(params[:id])
      removed_by = request.env["HTTP_AUTHORIZATION"]&.then { decode_basic_user(_1) } || "console"

      ActiveRecord::Base.transaction do
        NotificationAudit.create!(
          correlation_id:      SecureRandom.uuid,
          status:              "blacklist_removed",
          channel:             "email",
          source:              "internal",
          notification_type:   "_blacklist_removed_",
          recipient_canonical: entry.recipient_canonical,
          metadata:            { blacklist_id: entry.id, scope: entry.scope, target: entry.target,
                                 removed_by: removed_by, reason: params[:reason].to_s }
        )
        entry.destroy!
      end
      redirect_to admin_blacklist_index_path, status: :see_other
    end

    private

    def filter_params
      { recipient: params[:recipient].presence, scope: params[:scope].presence,
        target:    params[:target].presence,    source: params[:source].presence }.compact
    end

    def build_query(filters)
      q = NotificationBlacklist.order(created_at: :desc)
      q = q.where(recipient_canonical: filters[:recipient]) if filters[:recipient]
      q = q.where(scope: filters[:scope])                   if filters[:scope]
      q = q.where(target: filters[:target])                 if filters[:target]
      q = q.where(source: filters[:source])                 if filters[:source]
      q
    end

    def canonicalize(raw)
      return nil if raw.blank?

      RecipientNormalizer.normalize(raw)[:canonical]
    # :nocov:
    rescue ArgumentError
      nil
      # :nocov:
    end

    def decode_basic_user(header)
      return nil unless header&.start_with?("Basic ")

      Base64.decode64(header.split(" ", 2).last).split(":", 2).first
    # :nocov:
    rescue StandardError
      nil
      # :nocov:
    end
  end
end
