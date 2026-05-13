# frozen_string_literal: true

module Admin
  class DlqController < BaseController
    def controller_section = :dlq

    def index
      @reason_filter = params[:reason].presence
      @groups        = Admin::DlqQuery.grouped_by_reason(reason_filter: @reason_filter)
      @error_summary = build_error_summary
    end

    def build_error_summary
      counts = DispatchQueue.where(status: "failed")
                            .group(:failed_reason)
                            .count

      summary = { timeout: 0, rate_limit: 0, refused: 0, other: 0 }
      counts.each do |reason, count|
        case reason.to_s
        when /Timeout|timeout|OpenTimeout|ReadTimeout/ then summary[:timeout]    += count
        when /429|RateLimit|rate.limit/i               then summary[:rate_limit] += count
        when /ECONNREFUSED|Connection refused/i        then summary[:refused]    += count
        else                                                summary[:other]      += count
        end
      end
      summary.merge(total: summary.values.sum)
    end
    private :build_error_summary

    def retry
      job = DispatchQueue.find(params[:id])
      Admin::DlqRetrier.call(job, by: current_admin_user.email)
      redirect_to admin_dlq_index_path, status: :see_other, notice: "Job reencolado."
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_dlq_index_path, status: :see_other, alert: "Job no encontrado."
    end

    def bulk_retry
      reason = params[:reason].to_s.strip
      if reason.blank?
        redirect_to admin_dlq_index_path, status: :see_other, alert: "Motivo requerido para reintento masivo."
        return
      end

      result = Admin::DlqRetrier.bulk_call(reason: reason, by: current_admin_user.email)
      retried = result[:retried]
      total   = result[:total]

      msg = if total > retried
        "Se reintentaron #{retried} de #{total} jobs (cap #{Admin::DlqRetrier::CAP}). Ejecutá de nuevo para los restantes."
      else
        "Se reintentaron #{retried} jobs."
      end
      redirect_to admin_dlq_index_path, status: :see_other, notice: msg
    end

    def discard
      job = DispatchQueue.find(params[:id])
      reason = params[:reason].to_s.strip

      if reason.blank?
        redirect_to admin_dlq_index_path, status: :see_other, alert: "El motivo de descarte es requerido."
        return
      end

      Admin::DlqDiscarder.call(job, reason: reason, by: current_admin_user.email)
      redirect_to admin_dlq_index_path, status: :see_other, notice: "Job descartado."
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_dlq_index_path, status: :see_other, alert: "Job no encontrado."
    end
  end
end
