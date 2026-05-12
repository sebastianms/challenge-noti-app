# frozen_string_literal: true

module Admin
  class RulesController < Admin::BaseController
    before_action :set_rule, only: %i[edit update destroy history]

    def index
      @rules = NotificationRule.order(:notification_type)
    end

    def new
      @rule = NotificationRule.new
    end

    def create
      @rule = NotificationRule.new(rule_params)
      ActiveRecord::Base.transaction do
        @rule.save!
        RuleChange.create!(
          notification_rule: @rule,
          admin_user: current_admin_user,
          action: "created",
          before: nil,
          after: audited_snapshot(@rule)
        )
      end
      redirect_to admin_rules_path, notice: "Regla creada."
    rescue ActiveRecord::RecordInvalid
      render :new, status: :unprocessable_entity
    end

    def edit; end

    def update
      snapshot_before = audited_snapshot(@rule)
      ActiveRecord::Base.transaction do
        @rule.update!(rule_params)
        RuleChange.create!(
          notification_rule: @rule,
          admin_user: current_admin_user,
          action: "updated",
          before: snapshot_before,
          after: audited_snapshot(@rule)
        )
      end
      redirect_to admin_rules_path, notice: "Regla actualizada."
    rescue ActiveRecord::RecordInvalid
      render :edit, status: :unprocessable_entity
    end

    def destroy
      snapshot_before = audited_snapshot(@rule)
      ActiveRecord::Base.transaction do
        @rule.destroy!
        RuleChange.create!(
          notification_rule: nil,
          admin_user: current_admin_user,
          action: "deleted",
          before: snapshot_before,
          after: nil
        )
      end
      redirect_to admin_rules_path, notice: "Regla eliminada."
    end

    def history
      @changes = RuleChange.where(notification_rule: @rule).order(changed_at: :desc)
    end

    private

    AUDITED_FIELDS = %w[notification_type enabled priority max_per_day cooldown_seconds digest_window_seconds channels].freeze

    def set_rule
      @rule = NotificationRule.find(params[:id])
    end

    def rule_params
      params.require(:notification_rule).permit(
        :notification_type, :enabled, :priority,
        :max_per_day, :cooldown_seconds, :digest_window_seconds,
        channels: []
      )
    end

    def audited_snapshot(rule)
      rule.attributes.slice(*AUDITED_FIELDS)
    end

    def controller_section
      :rules
    end
  end
end
