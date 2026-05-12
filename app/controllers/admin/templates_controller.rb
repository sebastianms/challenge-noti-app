# frozen_string_literal: true

module Admin
  class TemplatesController < BaseController
    def controller_section = :templates

    before_action :set_template, only: [ :edit, :update, :destroy, :preview ]

    def index
      @templates = NotificationTemplate.order(:notification_type, :locale)
    end

    def new
      @template = NotificationTemplate.new(locale: "es")
    end

    def create
      @template = NotificationTemplate.new(template_params)
      if @template.save
        redirect_to admin_templates_path, status: :see_other, notice: "Template guardado."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @template.update(template_params)
        redirect_to admin_templates_path, status: :see_other, notice: "Template actualizado."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @template.destroy!
      redirect_to admin_templates_path, status: :see_other, notice: "Override eliminado."
    end

    def preview
      raw_ctx = begin
        JSON.parse(params.fetch(:context_json, "{}")).symbolize_keys
      rescue JSON::ParserError
        {}
      end

      result_title  = Templates::TemplateInterpolator.interpolate(params[:title].to_s,         raw_ctx)
      result_body   = Templates::TemplateInterpolator.interpolate(params[:body].to_s,          raw_ctx)
      result_digest = Templates::TemplateInterpolator.interpolate(params[:digest_template].to_s, raw_ctx)

      @preview = {
        title:           result_title[:result],
        body:            result_body[:result],
        digest_template: result_digest[:result],
        missing:         (result_title[:missing] + result_body[:missing] + result_digest[:missing]).uniq
      }

      render :preview, layout: false
    end

    private

    def set_template
      @template = NotificationTemplate.find(params[:id])
    end

    def template_params
      params.require(:notification_template).permit(:notification_type, :locale, :title, :body, :digest_template)
    end
  end
end
