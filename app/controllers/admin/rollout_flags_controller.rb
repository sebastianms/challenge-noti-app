# frozen_string_literal: true

module Admin
  class RolloutFlagsController < BaseController
    def controller_section = :rollout_flags

    def index
      @flags = NotificationRolloutFlag.order(:team_name, :notification_type)
    end

    def new
      @flag = NotificationRolloutFlag.new
    end

    def create
      @flag = NotificationRolloutFlag.new(flag_params)
      if @flag.save
        redirect_to admin_rollout_flags_path, notice: "Flag creado."
      else
        render :new, status: :unprocessable_content
      end
    end

    def update
      @flag = NotificationRolloutFlag.find(params[:id])
      if @flag.update(flag_params)
        redirect_to admin_rollout_flags_path, notice: "Flag actualizado."
      else
        redirect_to admin_rollout_flags_path, alert: "Error al actualizar."
      end
    end

    def destroy
      NotificationRolloutFlag.find(params[:id]).destroy
      redirect_to admin_rollout_flags_path, notice: "Flag eliminado.", status: :see_other
    end

    private

    def flag_params
      params.require(:notification_rollout_flag)
            .permit(:notification_type, :team_name, :enrolled, :notes)
    end
  end
end
