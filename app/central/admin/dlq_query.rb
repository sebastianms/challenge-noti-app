# frozen_string_literal: true

module Admin
  class DlqQuery
    ITEMS_PREVIEW_CAP = 10

    def self.grouped_by_reason(reason_filter: nil)
      scope = DispatchQueue.where(status: "failed")
      scope = scope.where("failed_reason LIKE ?", "#{reason_filter}%") if reason_filter.present?
      scope
        .select("split_part(COALESCE(failed_reason, ''), ':', 1) AS reason_class, COUNT(*) AS count")
        .group("reason_class")
        .order("count DESC")
        .map do |row|
          reason = row.reason_class.presence || "Unknown"
          {
            reason_class: reason,
            count:        row.count.to_i,
            items:        items_preview(reason)
          }
        end
    end

    def self.items_preview(reason_class)
      scope = DispatchQueue.where(status: "failed")
      scope = scope.where("split_part(COALESCE(failed_reason, ''), ':', 1) = ?", reason_class)
      scope.order(updated_at: :desc).limit(ITEMS_PREVIEW_CAP)
    end

    def self.reason_class_for(error_string)
      return "Unknown" if error_string.blank?

      error_string.split(":").first.strip.presence || "Unknown"
    end
  end
end
