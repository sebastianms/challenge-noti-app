# frozen_string_literal: true

class AuditSearch
  MAX_PER_PAGE     = 50
  DEFAULT_PER_PAGE = 50

  Result = Struct.new(:items, :total, :page, :per_page, keyword_init: true) do
    def has_next? = page * per_page < total
  end

  def initialize(correlation_id: nil, recipient: nil, status: nil, from: nil, to: nil, source: nil,
                 reason: nil, rule_id: nil, page: 1, per_page: DEFAULT_PER_PAGE)
    @correlation_id = correlation_id
    @recipient      = recipient
    @status         = status
    @from           = from
    @to             = to
    @source         = source
    @reason         = reason
    @rule_id        = rule_id&.to_i.presence
    @page           = [ page.to_i, 1 ].max
    @per_page       = [ [ per_page.to_i, 1 ].max, MAX_PER_PAGE ].min
  end

  def call
    return correlation_lookup if @correlation_id.present?

    filtered_query
  end

  private

  def correlation_lookup
    NotificationAudit
      .where(correlation_id: @correlation_id)
      .order(created_at: :asc)
      .to_a
  end

  def filtered_query
    scope = NotificationAudit.all
    scope = scope.where(recipient_canonical: @recipient) if @recipient.present?
    scope = scope.where(status: @status)                 if @status.present?
    scope = scope.where(source: @source)                 if @source.present?
    scope = scope.where("created_at >= ?", @from)        if @from.present?
    scope = scope.where("created_at < ?",  @to)          if @to.present?
    scope = scope.where("metadata->>'reason' = ?", @reason)           if @reason.present?
    scope = scope.where("(metadata->>'rule_id')::int = ?", @rule_id)  if @rule_id.present?

    total = scope.count
    items = scope.order(created_at: :desc).limit(@per_page).offset((@page - 1) * @per_page).to_a

    Result.new(items: items, total: total, page: @page, per_page: @per_page)
  end
end
