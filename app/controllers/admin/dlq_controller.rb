# frozen_string_literal: true

module Admin
  class DlqController < BaseController
    def controller_section = :dlq

    def index
      @reason_filter = params[:reason].presence
      @groups = Admin::DlqQuery.grouped_by_reason(reason_filter: @reason_filter)
    end

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
